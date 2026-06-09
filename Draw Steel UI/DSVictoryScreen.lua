local mod = dmhub.GetModLoading()

----------------------------------------------------------------------
-- DSVictoryScreen
--
-- A full-screen "the heroes have won" celebration. When the director presses
-- "Award Victory" on the initiative bar, the live encounter's victoryAwarded flag is
-- flipped (LiveEncounter.victoryAwarded, networked inside the initiative queue). Every
-- client polls that flag; when it is set the normal initiative display is hidden (see
-- MCDMInitiativeBar.lua) and this screen takes over: the screen darkens, a "Victory"
-- title sweeps in across the top, and the heroes fade in one by one with their
-- portraits, names, Stamina, and how their Recoveries changed over the fight. Dead
-- heroes are marked DEAD.
--
-- The director gets a "Proceed" button at the bottom; pressing it ends combat and
-- clears the victory state, which closes the screen for every client.
--
-- The screen is created once and mounted at the top of the game HUD (see GameHud.lua).
-- It reads its state straight from dmhub.initiativeQueue.liveEncounter, so no separate
-- synced document is needed -- the live encounter is already networked to all clients.
----------------------------------------------------------------------

RegisterGameType("DSVictoryScreen")

-- Seconds between each hero fading in.
local g_heroStagger = 0.28

-- The victory (Victories resource) icon, dropped into each hero's card on Award.
local VICTORY_ICON = "drawsteel/HeroicResources/T_UI_ICON_FLAT_HR_VICTORY.png"

-- Returns the live encounter if and only if it is currently in the victory state
-- (combat active + victory awarded); otherwise nil.
local function GetActiveVictory()
    local q = dmhub.initiativeQueue
    if q == nil or q.hidden then
        return nil
    end
    local live = q:try_get("liveEncounter")
    if type(live) ~= "table" or not live:try_get("victoryAwarded", false) then
        print("VICTORY:: GetActiveVictory -> nil")
        return nil
    end
        print("VICTORY:: GetActiveVictory -> live", live)
    return live
end

-- End combat and clear the victory state, mirroring the initiative bar's "End Combat"
-- menu item. Setting the queue hidden + clearing victoryAwarded and uploading is what
-- closes this screen (and re-hides the bar) on every client.
local function ProceedEndCombat()
    local q = dmhub.initiativeQueue
    if q == nil then
        return
    end

    local live = q:try_get("liveEncounter")
    if type(live) == "table" then
        live.victoryAwarded = false
    end

    q.hidden = true
    q.gameMode = "exploration"
    dmhub:UploadInitiativeQueue()

    CharacterResource.SetMalice(0, "End of Combat")

    local hud = GameHud.instance
    if hud ~= nil then
        for initiativeid, _ in pairs(q.entries) do
            local tokens = hud:GetTokensForInitiativeId(hud.initiativeInterface, initiativeid)
            for _, tok in ipairs(tokens) do
                if tok.properties ~= nil then
                    tok.properties:EndCombat()
                    tok.properties:DispatchEvent("endcombat", {})
                end
            end
        end
    end
end

-- Build a single hero's card: portrait, name, Stamina bar, Recoveries change, and a DEAD
-- marker for fallen heroes. Every visible element carries the "victoryFade" class so the
-- card-level "shown" class can fade the whole card in via the descendant style rules on
-- the card (opacity does not cascade in this engine, so each leaf is faded individually).
local function BuildHeroCard(live, token)
    local props = token and token.properties
    local name = (token and token.name) or "Hero"

    local dead = props ~= nil and props:IsDead()
    local curHp = (props ~= nil and props:CurrentHitpoints()) or 0
    local maxHp = (props ~= nil and props:MaxHitpoints()) or 0
    local fillPct = 0
    if maxHp > 0 and curHp > 0 then
        fillPct = math.min(1, curHp / maxHp) * 100
    end

    -- Portrait. Fills the full width of the card and grows tall to match the
    -- 3:4 portrait aspect (height = width * 100/portraitWidthPercentOfHeight).
    -- A negative top margin pulls it flush to the card's top inner edge, past
    -- the card's vpad, so it reads as a header image rather than an inset.
    local portraitPanel = gui.Panel{
        -- borderInfo paints the gold accent frame from the active scheme;
        -- bgcolor "white" stays inline (image-tint-neutral for the portrait).
        classes = {"victoryFade", "victoryPortrait", "borderInfo"},
        interactable = false,
        width = "100%",
        height = string.format("%f%% width", 10000 / Styles.portraitWidthPercentOfHeight),
        halign = "center",
        valign = "top",
        tmargin = -12,
        bgcolor = "white",
        borderWidth = 2,
        cornerRadius = 4,
    }
    if token ~= nil then
        local portrait = token.inspectPortrait
        portraitPanel.bgimage = portrait
        if token.hasSpineAnimation then
            portraitPanel.selfStyle.imageRect = nil
        else
            portraitPanel.selfStyle.imageRect = token:GetPortraitRectForAspect(Styles.portraitWidthPercentOfHeight * 0.01, portrait)
        end
    end

    local nameLabel = gui.Label{
        classes = {"victoryFade", "victoryHeroName"},
        interactable = false,
        text = name,
        width = "100%",
        height = "auto",
        halign = "center",
        tmargin = 8,
        textAlignment = "center",
        textWrap = false,
        fontFace = "Book",
        fontSize = 20,
        fontWeight = "bold",
    }

    -- Stamina bar: a dark track with a coloured fill and "current/max" overlaid.
    -- The fill takes the scheme's danger (dead) or success (alive) token.
    local staminaFill = gui.Panel{
        classes = {"victoryFade", cond(dead, "bgDanger", "bgSuccess")},
        interactable = false,
        halign = "left",
        valign = "center",
        height = "100%",
        width = string.format("%f%%", fillPct),
    }

    local staminaText = gui.Label{
        classes = {"victoryFade"},
        interactable = false,
        text = string.format("%d/%d", curHp, maxHp),
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        textAlignment = "center",
        fontFace = "Book",
        fontSize = 13,
    }

    local staminaBar = gui.Panel{
        -- bg = dark track surface, border = themed frame.
        classes = {"victoryFade", "bg", "border"},
        interactable = false,
        flow = "none",
        width = 150,
        height = 18,
        halign = "center",
        tmargin = 6,
        borderWidth = 1,
        cornerRadius = 3,
        children = { staminaFill, staminaText },
    }

    -- Recoveries: "Recoveries: onset -> current/max" (or just "current/max" if unchanged).
    local onset, curRec, maxRec = live:GetHeroRecoveries(token)
    local recText
    if onset ~= nil and onset ~= curRec then
        recText = string.format("Recoveries: %d -> %d/%d", onset, curRec, maxRec)
    else
        recText = string.format("Recoveries: %d/%d", curRec, maxRec)
    end

    local recoveriesLabel = gui.Label{
        classes = {"victoryFade", "fg"},
        interactable = false,
        text = recText,
        width = "100%",
        height = "auto",
        halign = "center",
        tmargin = 6,
        textAlignment = "center",
        textWrap = false,
        fontFace = "Book",
        fontSize = 14,
    }

    local deadLabel = gui.Label{
        classes = {"victoryFade", "victoryDead", "danger"},
        interactable = false,
        text = "DEAD",
        width = "100%",
        height = "auto",
        halign = "center",
        tmargin = 6,
        textAlignment = "center",
        fontFace = "Book",
        fontSize = 18,
        fontWeight = "black",
        uppercase = true,
    }
    deadLabel:SetClass("collapsed", not dead)

    -- "Victories: old -> new" line, hidden until the Award animation finishes.
    local victoriesLabel = gui.Label{
        classes = {"victoryFade", "scalein", "info"},
        interactable = false,
        text = "",
        width = "100%",
        height = "auto",
        halign = "center",
        tmargin = 8,
        textAlignment = "center",
        textWrap = false,
        fontFace = "Book",
        fontSize = 16,
        fontWeight = "bold",
    }
    victoriesLabel:SetClass("collapsed", true)

    -- Floating overlay that holds the victory icons as they drop into the card.
    local dropLayer = gui.Panel{
        interactable = false,
        floating = true,
        flow = "none",
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        children = {},
    }

    local victoriesOld = (props ~= nil and props:GetVictories()) or 0

    return gui.Panel{
        --"victoryFade" so the card's own gradient background fades in along with its
        --contents (opacity does not cascade, so the card needs the class too).
        -- panel + surfaceRadial paints the scheme's vignette "hero" surface so
        -- transparent character art reads against a solid backdrop; border adds
        -- the themed frame. All track the active color scheme.
        classes = {"panel", "surfaceRadial", "border", "victoryHeroCard", "scalein", "victoryFade"},
        interactable = false,
        flow = "vertical",
        width = 200,
        -- Fixed height + valign top: all cards align at the same top, and the conditional
        -- DEAD / Victories lines fill reserved space below rather than resizing the card.
        height = 380,
        halign = "center",
        valign = "top",
        hmargin = 12,

        cornerRadius = 8,
        borderWidth = 1,
        vpad = 12,
        borderBox = true,

        data = { token = token, victoriesOld = victoriesOld },

        styles = {
            -- Every leaf starts transparent and fades to full once the card gains the
            -- "shown" class (descendant rule -- ancestor "shown" + element "victoryFade").
            { selectors = {"victoryFade"}, opacity = 0, transitionTime = 0.6 },
            { selectors = {"shown", "victoryFade"}, opacity = 1, transitionTime = 0.6 },
            --scale up from 2x only on the way IN (before "shown"). On exit we strip the
            --"scalein" class entirely (see fadeOut) so this rule can't match and the card
            --fades at scale 1 instead of ballooning.
            { selectors = {"scalein", "~shown"}, transitionTime = 0.6, scale = 1.3,},
        },

        -- dropLayer is LAST so it draws on top of the card content (in DMHub later
        -- siblings render above earlier ones), letting the icons land over the card.
        children = { portraitPanel, nameLabel, staminaBar, recoveriesLabel, deadLabel, victoriesLabel, dropLayer },

        -- Drop `amount` victory icons into this card one at a time, then reveal the
        -- "Victories: old -> new" line. Orchestrated per-card by the screen's playAward.
        awardVictories = function(card, amount)
            if amount == nil or amount <= 0 then
                card:FireEvent("finishAward", 0)
                return
            end
            local icons = {}
            for i = 1, amount do
                icons[i] = gui.Panel{
                    classes = {"victoryDropIcon", "dropStart"},
                    interactable = false,
                    bgimage = VICTORY_ICON,
                    bgcolor = "white",
                    width = 96,
                    height = 96,
                    halign = "center",
                    valign = "center",
                    styles = {
                        --non-floating children animate y via class toggles (the swords
                        --in DSInitiativeRoll use the same pattern).
                        { classes = {"dropStart"}, y = -600, opacity = 0, transitionTime = 0.45, easing = "EaseInCubic" },
                        { classes = {"dropLand"}, opacity = 1, transitionTime = 0.45, easing = "EaseOutCubic" },
                        --fade out where it landed (keep y) over a slower, graceful fade
                        --rather than snapping away.
                        { classes = {"dropGone"}, opacity = 0, transitionTime = 0.7 },
                        { y = -140 },
                    },
                }
            end
            dropLayer.children = icons

            local stagger = 0.35
            for i, icon in ipairs(icons) do
                card:ScheduleEvent("dropIcon", (i - 1) * stagger, icon)
                card:ScheduleEvent("fadeIcon", (i - 1) * stagger + 0.5, icon)
            end
            card:ScheduleEvent("finishAward", amount * stagger + 0.3, amount)
        end,

        dropIcon = function(card, icon)
            if icon ~= nil and icon.valid then
                icon:SetClass("dropStart", false)
                icon:SetClass("dropLand", true)
            end
        end,

        fadeIcon = function(card, icon)
            if icon ~= nil and icon.valid then
                icon:SetClass("dropLand", false)
                icon:SetClass("dropGone", true)
            end
        end,

        finishAward = function(card, amount)
            local newV = card.data.victoriesOld + amount
            victoriesLabel.text = string.format("Victories: %d -> %d", card.data.victoriesOld, newV)
            victoriesLabel:SetClass("collapsed", false)
            victoriesLabel:SetClass("shown", false)
            victoriesLabel:SetClass("shown", true)
        end,

        -- Fade the whole card out (its gradient background fades via "victoryFade" on the
        -- card itself, its leaves via the same class) plus any icons still in flight, so
        -- nothing snaps away when the screen dismisses.
        fadeOut = function(card)
            --strip "scalein" across the tree first so the {scalein, ~shown} scale-up rule
            --can no longer match; the card then fades at scale 1 rather than growing to 2x.
            --card:SetClassTree("scalein", false)
            card:SetClassTree("shown", false)
            for _, icon in ipairs(dropLayer.children) do
                if icon ~= nil and icon.valid then
                    icon:SetClass("dropStart", false)
                    icon:SetClass("dropLand", false)
                    icon:SetClass("dropGone", true)
                end
            end
        end,
    }
end

-- Create the victory screen overlay. Mounted once by the game HUD.
function DSVictoryScreen.Create()
    local heroRow
    local titleLabel
    local titleGroup
    local proceedButton
    local rootPanel
    local victoriesSection
    local victoryAmountInput

    ------------------------------------------------------------------
    -- Full-screen dim. Interactable so it swallows clicks to the map
    -- underneath while the celebration is up. blurBackground (toggled on
    -- in showVictory / off in finishHide, since this panel persists hidden
    -- between victories) makes MainCamera render a blurred copy of the map
    -- that this full-screen panel composites behind its tint, so the whole
    -- map blurs. The dim is kept light enough that the blur reads through.
    ------------------------------------------------------------------
    local dimPanel = gui.Panel{
        classes = {"dim-out"},
        interactable = true,
        width = "100%",
        height = "100%",
        bgimage = "panels/square.png",
        bgcolor = "black",
        styles = {
            { classes = {"dim-out"}, opacity = 0, transitionTime = 0.4 },
            { classes = {"dim-in"}, opacity = 0.55, transitionTime = 0.5 },
        },
    }

    ------------------------------------------------------------------
    -- VICTORY title, flanked by two swords that sweep apart to reveal
    -- it -- the same reveal used by the Draw Steel initiative banner
    -- (Draw Steel UI/DSInitiativeRoll.lua) and the DramaticBanner
    -- (DMHub Game Hud/FullscreenDisplay.lua). The title itself is drawn
    -- twice: a black copy offset down-right behind the white face gives
    -- it a hard drop-shadow.
    ------------------------------------------------------------------
    local titleFontSize = 80

    -- Build a title label. The shadow copy is the same glyphs in black,
    -- nudged a few px down-right and rendered behind the white face.
    local function MakeTitleLabel(isShadow)
        return gui.Label{
            classes = {"victoryTitle"},
            interactable = false,
            text = "Victory",
            halign = "center",
            valign = "center",
            x = cond(isShadow, 6, 0),
            y = cond(isShadow, 6, 0),
            width = "auto",
            height = "auto",
            textAlignment = "center",
            -- Never wrap: the clip window can be narrower than the text mid-
            -- reveal, and a wrapping label would reflow instead of clipping.
            textWrap = false,
            fontFace = "Book",
            fontSize = titleFontSize,
            fontWeight = "black",
            uppercase = true,
            -- Face uses the themed @fgStrong (label default); the shadow copy
            -- stays black -- a drop shadow is intentionally scheme-independent.
            color = cond(isShadow, "black", nil),
            styles = {
                { selectors = {"victoryTitle"}, opacity = 0, transitionTime = 0.7 },
                { selectors = {"victoryTitle", "shown"}, opacity = 1, transitionTime = 0.7 },
            },
        }
    end

    local titleShadow = MakeTitleLabel(true)
    titleLabel = MakeTitleLabel(false)

    -- Two swords that rest crossed at the title's centre and sweep apart
    -- to either side, wiping the (clipped) title into view between them.
    -- The right sword mirrors the left (negative x scale).
    local swordOpenOffset = 380

    local function MakeVictorySword(isLeft)
        local closedClass = cond(isLeft, "lsw-closed", "rsw-closed")
        local openClass = cond(isLeft, "lsw-open", "rsw-open")
        local openX = cond(isLeft, -swordOpenOffset, swordOpenOffset)
        return gui.Panel{
            classes = {closedClass},
            interactable = false,
            width = 240,
            height = "50% width",
            halign = "center",
            valign = "center",
            y = -10,
            bgimage = "panels/initiative/drawsteel-sword.png",
            bgcolor = "white",
            scale = cond(isLeft, nil, {x = -1, y = 1}),
            styles = {
                -- Visible while crossed so they read as crossed swords that
                -- wipe the title open. easeInBack winds them back in slightly
                -- before they settle; easeOutCubic gives the sweep a smooth tail.
                { selectors = {closedClass}, x = 0, opacity = 1, transitionTime = 0.45, easing = "EaseInBack" },
                { selectors = {openClass}, x = openX, opacity = 1, transitionTime = 0.6, easing = "EaseOutCubic" },
            },
        }
    end

    local leftSword = MakeVictorySword(true)
    local rightSword = MakeVictorySword(false)

    -- The title is revealed by a horizontally-growing clip window rather
    -- than just sitting under the swords: like the DramaticBanner, the text
    -- stays hidden behind the crossed swords and is wiped into view from the
    -- centre out as they part, so the swords never appear over it. clip=true
    -- makes this panel's bgimage a mask for its children (clipHidden hides
    -- the mask itself); the window grows symmetrically about the centre.
    -- EaseInCubic makes the reveal trail the (EaseOutCubic) swords, so the
    -- text only emerges in space the swords have already cleared.
    local titleClip = gui.Panel{
        classes = {"titleClip-closed"},
        interactable = false,
        flow = "none",
        halign = "center",
        valign = "center",
        height = 150,
        bgimage = "panels/square.png",
        clip = true,
        clipHidden = true,
        children = { titleShadow, titleLabel },
        styles = {
            { selectors = {"titleClip-closed"}, width = 0,   transitionTime = 0.6, easing = "EaseInCubic" },
            { selectors = {"titleClip-open"},   width = 760, transitionTime = 0.6, easing = "EaseInCubic" },
        },
    }

    -- Flow "none" overlay so the swords animate in x relative to the shared
    -- centre. Child order is draw order: the clipped title behind, swords on
    -- top, so the swords visibly part to wipe the title open.
    titleGroup = gui.Panel{
        interactable = false,
        flow = "none",
        width = "100%",
        height = 160,
        halign = "center",
        valign = "top",
        y = 40,
        children = { titleClip, leftSword, rightSword },
    }

    -- The cards rest at a stable top within this row (fixed height + valign top), so a
    -- card growing -- e.g. when its "Victories" line appears -- never shifts the others.
    heroRow = gui.Panel{
        interactable = false,
        flow = "horizontal",
        width = "auto",
        height = 400,
        maxWidth = 1760,
        halign = "center",
        valign = "top",
        y = 210,
        wrap = true,
        children = {},
    }

    -- Director-only "Proceed" button: ends combat and clears the victory state.
    -- Themed text button; the local styles only drive the fade-in (the themed
    -- button rules supply rest/hover/press chrome from the active scheme).
    proceedButton = gui.Button{
        classes = {"sizeL", "victoryProceed"},
        text = "Proceed",
        interactable = true,
        width = 220,
        height = 56,
        halign = "center",
        valign = "bottom",
        y = -70,

        styles = {
            { selectors = {"victoryProceed"}, opacity = 0, transitionTime = 0.5 },
            { selectors = {"victoryProceed", "shown"}, opacity = 1, transitionTime = 0.5 },
        },

        hover = function(element)
            gui.Tooltip{ text = "End combat and dismiss the victory screen for everyone." }(element)
        end,

        click = function(element)
            ProceedEndCombat()
        end,
    }

    ------------------------------------------------------------------
    -- Director-only "Victories" controls, sitting just above Proceed.
    -- An editable count of how many Victories to grant each hero, plus
    -- an Award button that grants them and triggers the icon-drop
    -- animation on every client.
    ------------------------------------------------------------------
    local victoriesTitleLabel = gui.Label{
        interactable = false,
        text = "Victories:",
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
        textAlignment = "center",
        fontFace = "Book",
        fontSize = 18,
    }

    victoryAmountInput = gui.Input{
        classes = {"form"},
        interactable = true,
        width = 60,
        height = 32,
        halign = "center",
        valign = "center",
        hmargin = 8,
        fontSize = 16,
        numeric = true,
        characterLimit = 3,
        text = "1",
        change = function(element)
            local n = tonumber(element.text)
            if n == nil then
                element.text = "1"
                return
            end
            n = math.floor(n)
            if n < 0 then n = 0 end
            element.text = tostring(n)
        end,
    }

    -- Themed text button; rest/hover/press chrome comes from the active scheme.
    local awardVictoriesButton = gui.Button{
        classes = {"sizeM"},
        text = "Award",
        interactable = true,
        width = 120,
        height = 40,
        halign = "center",
        valign = "center",
        hmargin = 10,

        hover = function(element)
            gui.Tooltip{ text = "Grant this many Victories to each hero." }(element)
        end,

        click = function(element)
            if not dmhub.isDM then return end
            local live = GetActiveVictory()
            if live == nil then return end
            local n = tonumber(victoryAmountInput.text) or 1
            n = math.floor(n)
            if n < 0 then n = 0 end

            for _, token in ipairs(live:GetBattleHeroTokens()) do
                token:ModifyProperties{
                    description = "Award Victories",
                    combine = true,
                    execute = function()
                        token.properties:SetVictories(token.properties:GetVictories() + n)
                    end,
                }
            end

            --record the awarded amount + flag on the live encounter and network it so
            --every client plays the drop animation and shows the change.
            live.victories = n
            live.victoriesAwarded = true
            dmhub:UploadInitiativeQueue()
            if rootPanel ~= nil then
                rootPanel:FireEvent("checkVictory")
            end
        end,
    }

    victoriesSection = gui.Panel{
        classes = {"victoryAwardSection", "collapsed"},
        interactable = true,
        flow = "horizontal",
        width = "auto",
        height = 44,
        halign = "center",
        valign = "bottom",
        y = -150,
        children = { victoriesTitleLabel, victoryAmountInput, awardVictoriesButton },
    }

    rootPanel = gui.Panel{
        -- This overlay owns its cascade root, so the theme classes applied to
        -- the dim, cards, buttons, and labels below resolve against the active
        -- scheme. Re-resolved on theme change via OnThemeChanged below.
        styles = ThemeEngine.GetStyles(),
        classes = {"hidden"},
        floating = true,
        flow = "none",
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        -- interactable so the dim child and the Proceed button receive clicks (a parent
        -- with interactable=false would block its whole subtree from raycasts).
        interactable = true,

        children = { dimPanel, titleGroup, heroRow, victoriesSection, proceedButton },

        data = {
            -- Bumped on every show/hide so a stale scheduled callback can tell that a
            -- newer state change has superseded it.
            generation = 0,
            shown = false,
            awardPlayed = false,
        },

        -- Build + stagger the hero cards, then fade everything in.
        showVictory = function(element, live)
            element.data.generation = element.data.generation + 1
            local g = element.data.generation

            element:SetClass("hidden", false)
            dimPanel.blurBackground = true
            dimPanel:SetClass("dim-out", false)
            dimPanel:SetClass("dim-in", true)

            titleLabel:SetClass("shown", false)
            titleShadow:SetClass("shown", false)
            titleClip:SetClass("titleClip-open", false)
            titleClip:SetClass("titleClip-closed", true)
            leftSword:SetClass("lsw-open", false)
            leftSword:SetClass("lsw-closed", true)
            rightSword:SetClass("rsw-open", false)
            rightSword:SetClass("rsw-closed", true)
            proceedButton:SetClass("shown", false)
            proceedButton:SetClass("collapsed", not dmhub.isDM)

            --reset the Director victories controls for this showing.
            element.data.awardPlayed = false
            victoryAmountInput.text = tostring(live:try_get("victories", 1))
            victoriesSection:SetClass("collapsed", true)

            --build a card per hero in the battle (enumerated live from the initiative
            --queue, so heroes always appear; the onset snapshot is only used to show how
            --their Recoveries changed).
            local heroTokens = live:GetBattleHeroTokens()
            print("VICTORY:: building cards for", #heroTokens, "heroes")
            local cards = {}
            for _, token in ipairs(heroTokens) do
                cards[#cards + 1] = BuildHeroCard(live, token)
            end
            heroRow.children = cards

            --title sweeps in first.
            element:ScheduleEvent("showTitle", 0.15, g)

            --then the heroes, one by one.
            for i, card in ipairs(cards) do
                element:ScheduleEvent("showHero", 0.4 + (i - 1) * g_heroStagger, g, card)
            end

            --finally the proceed button, after the last hero.
            local proceedDelay = 0.4 + (#cards) * g_heroStagger + 0.2
            element:ScheduleEvent("showProceed", proceedDelay, g)
        end,

        showTitle = function(element, g)
            if g ~= element.data.generation then return end
            titleLabel:SetClass("shown", true)
            titleShadow:SetClass("shown", true)
            titleClip:SetClass("titleClip-closed", false)
            titleClip:SetClass("titleClip-open", true)
            leftSword:SetClass("lsw-closed", false)
            leftSword:SetClass("lsw-open", true)
            rightSword:SetClass("rsw-closed", false)
            rightSword:SetClass("rsw-open", true)
        end,

        showHero = function(element, g, card)
            if g ~= element.data.generation then return end
            if card ~= nil and card.valid then
                --SetClassTree so every leaf (which carries "victoryFade") gets "shown" on
                --ITSELF -- the fade rule {"victoryFade","shown"} matches same-element, like
                --the title. A plain SetClass would only mark the card, leaving leaves hidden.
                card:SetClassTree("shown", true)
            end
        end,

        showProceed = function(element, g)
            if g ~= element.data.generation then return end
            proceedButton:SetClass("shown", true)
            --reveal the Director victories controls alongside Proceed (unless already
            --awarded, or this is a player).
            local live = GetActiveVictory()
            local awarded = live ~= nil and live:try_get("victoriesAwarded", false)
            victoriesSection:SetClass("collapsed", (not dmhub.isDM) or awarded)
        end,

        hideVictory = function(element)
            element.data.generation = element.data.generation + 1
            titleLabel:SetClass("shown", false)
            titleShadow:SetClass("shown", false)
            titleClip:SetClass("titleClip-open", false)
            titleClip:SetClass("titleClip-closed", true)
            leftSword:SetClass("lsw-open", false)
            leftSword:SetClass("lsw-closed", true)
            rightSword:SetClass("rsw-open", false)
            rightSword:SetClass("rsw-closed", true)
            proceedButton:SetClass("shown", false)
            victoriesSection:SetClass("collapsed", true)
            --fade each card (gradient background + contents + any icons) out alongside
            --the dim, rather than letting them snap away at finishHide.
            for _, card in ipairs(heroRow.children) do
                if card ~= nil and card.valid then
                    card:FireEvent("fadeOut")
                end
            end
            dimPanel:SetClass("dim-in", false)
            dimPanel:SetClass("dim-out", true)
            --hide the whole tree after the cards + dim have faded.
            element:ScheduleEvent("finishHide", 0.7, element.data.generation)
        end,

        finishHide = function(element, g)
            if g ~= element.data.generation then return end
            element:SetClass("hidden", true)
            --stop generating the full-screen blur texture now that the dim has
            --fully faded out; otherwise MainCamera keeps blurring every frame.
            dimPanel.blurBackground = false
            heroRow.children = {}
        end,

        -- Compare the current victory state to what we are showing and flip if needed.
        -- Driven by monitorGame (fires on every initiative-queue change, even while this
        -- panel is hidden -- a plain think would not fire while hidden) and once on create
        -- so a client that loads mid-victory shows the screen immediately.
        checkVictory = function(element)
            local live = GetActiveVictory()
            local active = live ~= nil
            if active and not element.data.shown then
                element.data.shown = true
                element:FireEvent("showVictory", live)
            elseif not active and element.data.shown then
                element.data.shown = false
                element:FireEvent("hideVictory")
            end

            --once the Director awards Victories, play the icon-drop animation (once).
            if active and element.data.shown and not element.data.awardPlayed
                and live:try_get("victoriesAwarded", false) then
                element.data.awardPlayed = true
                element:FireEvent("playAward", live)
            end
        end,

        -- Drop victory icons into each hero card in turn, one card after another.
        playAward = function(element, live)
            local g = element.data.generation
            local n = live:try_get("victories", 1)
            --the controls have done their job; hide them.
            victoriesSection:SetClass("collapsed", true)
            local cards = heroRow.children
            local perCard = 0.7
            for i, card in ipairs(cards) do
                element:ScheduleEvent("awardCard", (i - 1) * perCard, g, card, n)
            end
        end,

        awardCard = function(element, g, card, n)
            if g ~= element.data.generation then return end
            if card ~= nil and card.valid then
                card:FireEvent("awardVictories", n)
            end
        end,

        --Re-check whenever the initiative queue changes (victory awarded / combat ended).
        monitorGame = "/initiativeQueue",
        refreshGame = function(element)
            element:FireEvent("checkVictory")
        end,

        create = function(element)
            element:FireEvent("checkVictory")
        end,
    }

    -- Re-resolve the cascade when the user switches theme / color scheme so the
    -- whole victory screen recolors live.
    ThemeEngine.OnThemeChanged(mod, function()
        if rootPanel ~= nil and rootPanel.valid then
            rootPanel.styles = ThemeEngine.GetStyles()
        end
    end)

    return rootPanel
end
