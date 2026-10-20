local mod = dmhub.GetModLoading()

--Encounter of the Week custom interface: usurps the normal game hud via
--the GameHud.RegisterCustomInterface core hook (DMHub Core UI/Hud.lua).
--While active it removes the icon-rail button columns (the docks slide
--away with them), removes the "Panels" title-bar menu, removes Compendium
--access (menus, toolbar, search), and mounts a hero roster on the right
--edge of the screen (shrinking itself to fit when a full seven-hero
--roster is taller than the window): one card per hero showing portrait,
--name, stamina (with a recoveries circle beside it),
--heroic resource, surges, and condition icons. The local
--player's own heroes sit at the top, closer together, on a distinct
--backing. Clicking a card pops out the full character panel, which the
--characterPanelAccess override forces read-only for everyone.
--Design/plan doc: EncounterOfTheWeek/EncounterOfTheWeek.md.

--The custom interface shows only in a real EotW game or during an
--authoring test (IsEotwGame covers both); the authoring game is otherwise
--a normal Director game. (The old "/toggle eotw:forcecustomui" dev toggle
--that forced it on anywhere was retired for the authoring test.)

--- Hero cards ---------------------------------------------------------------

--The hero card (and the helpers this file still uses) moved to the core
--Codex Titlescreen mod, Codex Titlescreen/EotwHeroCard.lua, so the
--Blackbottom town on the titlescreen can show the same card.
local CreateHeroCard = EotwHeroCard.CreateHeroCard
local CreateStaminaBar = EotwHeroCard.CreateStaminaBar
local CreateCardFlash = EotwHeroCard.CreateCardFlash
local CollectHeroes = EotwHeroCard.CollectHeroes
local RosterSignature = EotwHeroCard.RosterSignature
local g_heroCardRules = EotwHeroCard.rules
local CARD_WIDTH = EotwHeroCard.CARD_WIDTH
local CARD_HEIGHT = EotwHeroCard.CARD_HEIGHT


--A half-size card for a monster that joined a hero during a montage
--(EncounterMontage): portrait, name and stamina bar. Sits under the hero's
--card in the roster and on the montage stage.
local ALLY_CARD_WIDTH = 62
local ALLY_CARD_HEIGHT = 80

local function CreateAllyCard(charid)
    local nameLabel = gui.Label{
        classes = {"eotwHeroName"},
        fontSize = 10,
        height = 12,
        text = "",
        interactable = false,
    }
    local overlay = gui.Panel{
        classes = {"eotwCardOverlay"},
        floating = true,
        halign = "center",
        valign = "bottom",
        width = "100%",
        height = 30,
        flow = "vertical",
        bgimage = "panels/square.png",
        cornerRadius = 6,
        hpad = 3,
        vpad = 2,
        borderBox = true,
        interactable = false,
        nameLabel,
        CreateStaminaBar(charid),
    }
    local hurtFlash = CreateCardFlash("eotwHurtFlash", 6)
    local healFlash = CreateCardFlash("eotwHealFlash", 6)
    return gui.Panel{
        classes = {"eotwHeroCard", "eotwAllyCard"},
        width = ALLY_CARD_WIDTH,
        height = ALLY_CARD_HEIGHT,
        halign = "left",
        hmargin = 1,
        cornerRadius = 6,
        bgimage = "panels/square.png",
        swallowPress = true,
        data = { charid = charid },
        press = function(element)
            audio.FireSoundEvent("Mouse.Click")
            local toggle = rawget(_G, "ToggleCharacterPanelDocument")
            if toggle ~= nil then
                toggle(charid, nil, element)
            end
        end,
        linger = function(element)
            gui.Tooltip(nameLabel.text)(element)
        end,
        refreshCard = function(element)
            local tok = dmhub.GetCharacterById(charid)
            if tok == nil or not tok.valid then
                element:SetClass("collapsed", true)
                return
            end
            element:SetClass("collapsed", false)
            --an ally is a MONSTER that joined a hero, so no "Unnamed Hero".
            nameLabel.text = tok.name or ""
            local portrait = nil
            pcall(function() portrait = tok.offTokenPortrait end)
            if portrait ~= nil and portrait ~= "" then
                element.bgimage = portrait
                element.selfStyle.bgcolor = "white"
                local rect = nil
                pcall(function() rect = tok:GetPortraitRectForAspect(ALLY_CARD_WIDTH / ALLY_CARD_HEIGHT, portrait) end)
                element.selfStyle.imageRect = rect
            end
        end,
        --fired up from the stamina bar in the overlay.
        staminaLost = function(element)
            hurtFlash:PulseClass("hurt")
        end,
        staminaGained = function(element)
            healFlash:PulseClass("healed")
        end,
        overlay,
        hurtFlash,
        healFlash,
    }
end

--The montage allies of a hero (charids), or an empty list.
local function AlliesOf(charid)
    local montage = rawget(_G, "EncounterMontage")
    if montage == nil or montage.GetAllies == nil then
        return {}
    end
    local allies = {}
    pcall(function() allies = montage.GetAllies(charid) end)
    return allies or {}
end

--- The roster panel ---------------------------------------------------------

--The vertical space the column has to live in, in the rail wrapper's own
--(pre-Font-Size-zoom) units. The wrapper is anchored under the title bar
--at the rail's top inset and renders at the rail-mode Font Size zoom, so
--the budget is the layer height less that inset and a bottom breathing
--gap, divided back out of the zoom.
--
--Layer height is measured the way the rail measures it (the documents
--layer is ~1048 units tall, not 1080 -- see IconRailUIHeight in
--DocumentSystem). The inset mirrors IconRailTop() there; the constants
--are duplicated rather than shared because both are file locals.
local ROSTER_BOTTOM_GAP = 12
--the smallest the column will shrink to before it just overflows: past
--this the cards are unreadable and clipping is the better failure.
local ROSTER_MIN_SCALE = 0.4

--the encounter-pools strip (malice + hero tokens) sits ABOVE the roster in
--the same right-rail wrapper, so its height plus the gap below it comes
--off the roster's budget (see CreateEncounterPoolsPanel).
local POOLS_HEIGHT = 40
local POOLS_GAP = 8
--one pool's slot in the strip. Two pools make a strip exactly as wide as a
--hero card; a third (Intelligence) makes it half a card wider.
local POOL_CELL_WIDTH = CARD_WIDTH / 2

local function RosterHeightBudget()
    local layerHeight = 1048
    pcall(function()
        local h = GameHud.instance.documentsPanel.renderedHeight
        if type(h) == "number" and h > 100 then
            layerHeight = h
        end
    end)

    local zoom = 1
    pcall(function()
        zoom = PanelDocument.WindowUIScale() or 1
    end)
    if type(zoom) ~= "number" or zoom <= 0 then
        zoom = 1
    end

    --IconRailTop(): max(64, (ICON_RAIL_BUTTON + RAIL_STOP_GAP) * zoom + RAIL_STOP_GAP)
    local topInset = (40 + 12) * zoom + 12
    if topInset < 64 then
        topInset = 64
    end

    local budget = (layerHeight - topInset - POOLS_HEIGHT - POOLS_GAP - ROSTER_BOTTOM_GAP) / zoom
    if budget < 100 then
        budget = 100
    end
    return budget
end

--Built fresh by the custom-interface rail host each time the rails build.
--Rebuilds its cards when party membership changes; individual card stats
--refresh on a 1s think plus the /characters monitor for prompt updates.
--With a full seven-hero roster the column is taller than the screen, so
--it shrinks itself to fit (see FitToScreen).
local function CreateHeroRosterPanel()
    local m_signature = nil
    --the column's unscaled height, accumulated as the cards are built.
    local m_contentHeight = 0
    local m_appliedScale = nil
    local m_fittedWhenAttached = false

    --Shrink the whole column, anchored to its top-RIGHT corner (the side
    --it hangs from), until it fits the screen. uiscale is a render-time
    --zoom around the pivot -- the same recipe the rail roots use for the
    --Font Size zoom -- so the layout inside the cards is untouched.
    --NOTE: selfStyle.uiscale is write-only; never read it back.
    local function FitToScreen(element)
        local scale = 1
        if m_contentHeight > 0 then
            local budget = RosterHeightBudget()
            if m_contentHeight > budget then
                scale = budget / m_contentHeight
                if scale < ROSTER_MIN_SCALE then
                    scale = ROSTER_MIN_SCALE
                end
            end
        end
        if scale == m_appliedScale then
            return
        end
        m_appliedScale = scale
        element.selfStyle.pivot = {x = 1, y = 1}
        element.selfStyle.uiscale = scale
    end

    local function Refresh(element)
        --Collapsed for the duration of a montage beat (the rail below
        --owns the class): nothing to rebuild, and dropping the signature
        --makes the column rebuild from scratch when it comes back.
        if element:HasClass("collapsed") then
            m_signature = nil
            return
        end

        --dead heroes stay in the column with a skull on their card.
        local heroes = CollectHeroes{ includeDead = true }
        local sig = RosterSignature(heroes)
        if sig ~= m_signature then
            m_signature = sig
            local cards = {}
            local seenOther = false
            local height = 0
            for _, entry in ipairs(heroes) do
                local card = CreateHeroCard(entry)
                if entry.mine then
                    card.selfStyle.vmargin = 2
                    height = height + CARD_HEIGHT + 4
                else
                    --a wider gap separates the local player's group from
                    --everyone else's heroes.
                    if not seenOther then
                        card.selfStyle.tmargin = 16
                        card.selfStyle.bmargin = 3
                        seenOther = true
                        height = height + CARD_HEIGHT + 19
                    else
                        card.selfStyle.vmargin = 3
                        height = height + CARD_HEIGHT + 6
                    end
                end
                cards[#cards+1] = card
                --monsters that joined this hero in the montage ride under
                --its card as half-size cards.
                local allies = AlliesOf(entry.charid)
                if #allies > 0 then
                    local minis = {}
                    for _, allyId in ipairs(allies) do
                        minis[#minis+1] = CreateAllyCard(allyId)
                    end
                    cards[#cards+1] = gui.Panel{
                        width = CARD_WIDTH,
                        height = "auto",
                        flow = "horizontal",
                        wrap = true,
                        halign = "right",
                        bmargin = 3,
                        children = minis,
                    }
                    height = height + (ALLY_CARD_HEIGHT + 3) * math.ceil(#allies / 2)
                end
            end
            m_contentHeight = height
            element.children = cards
        end
        --cheap enough to re-check every tick: the budget also moves when
        --the window is resized or the Font Size zoom changes, neither of
        --which touches the roster signature.
        FitToScreen(element)
        element:FireEventTree("refreshCard")
    end

    return gui.Panel{
        id = "eotwHeroRoster",
        width = "auto",
        height = "auto",
        flow = "vertical",
        halign = "right",
        valign = "top",

        styles = ThemeEngine.MergeTokens(g_heroCardRules),

        create = function(element)
            Refresh(element)
        end,

        --the rail wrapper's own 0.5s cadence. Its first tick is the first
        --moment the column is certainly attached to the documents layer,
        --which is when a pivot write actually sticks (the same reason the
        --rail roots fire setRailScale after AddChild), so the fit is
        --forced once more there.
        refreshRail = function(element)
            if not m_fittedWhenAttached then
                m_fittedWhenAttached = true
                m_appliedScale = nil
            end
            FitToScreen(element)
        end,

        --any character change (stamina, conditions, new heroes) lands
        --here; the think below is the fallback for combat-scoped resource
        --changes that do not touch /characters.
        monitorGame = "/characters",
        refreshGame = function(element)
            Refresh(element)
        end,

        thinkTime = 1,
        think = function(element)
            if mod.unloaded then
                element:DestroySelf()
                return
            end
            Refresh(element)
        end,
    }
end

--- Encounter pools: malice + hero tokens -------------------------------------

--A strip above the roster showing the two encounter-wide pools everyone
--cares about and which no card can carry: the monsters' Malice and the
--party's shared Hero Tokens. Read-only for everyone (strict rules: malice
--is spent by the Monster AI, hero tokens through the game's own flows);
--hovering a cell shows the pool's change history. Both pools live in the
--shared global-resource document, so that document is monitored for
--prompt updates; the 1s think covers the combat-state gating (malice
--reads as 0 outside combat without the document changing).
local function PoolValue(kind)
    local value = 0
    pcall(function()
        if kind == "malice" then
            value = CharacterResource.GetMalice() or 0
        elseif kind == "intelligence" then
            value = EncounterMontage.GetIntelligence()
        else
            value = CharacterResource.GetGlobalResource(CharacterResource.heroTokenId) or 0
        end
    end)
    return value
end

local function PoolHistory(kind)
    local history = {}
    pcall(function()
        if kind == "intelligence" then
            history = EncounterMontage.GetIntelligenceHistory()
            return
        end
        local id = cond(kind == "malice", CharacterResource.maliceResourceId, CharacterResource.heroTokenId)
        history = CharacterResource.GetGlobalResourceHistory(id) or {}
    end)
    return history
end

--Intelligence is an optional feature: only a week whose script asked for it
--("Unlock: Intelligence") has a pool, and until it does the strip carries
--the two pools it always has.
local function IntelligenceUnlocked()
    local on = false
    pcall(function() on = EncounterMontage.FeatureUnlocked("intelligence") end)
    return on
end

--Which pool (if any) the stage is explaining right now. While a narrative
--section's "Unlock: <Feature>" callout is up, that pool's cell blinks a white
--rectangle so the party can see WHICH number the explanation is about.
local function AnnouncedFeature()
    local feature = nil
    pcall(function()
        local narrative = rawget(_G, "EncounterNarrative")
        if narrative ~= nil and narrative.ActiveAnnounce ~= nil then
            local announce = narrative.ActiveAnnounce()
            feature = announce ~= nil and announce.feature or nil
        end
    end)
    return feature
end

--the malice cost diamond the action bar / initiative bar use, shrunk to
--fit the strip: a rotated square with the split-shade gradient and the
--red inner diamond, no number inside (the count sits beside it).
local function CreateMaliceDiamond()
    return gui.Panel{
        classes = {"costDiamond", "malice"},
        styles = { Styles.ActionMenu },
        interactable = false,
        rotate = 135,
        width = 18,
        height = 18,
        halign = "center",
        valign = "center",
        hmargin = 0,
        bgcolor = "white",
        border = { x1 = 0, y1 = 2, x2 = 2, y2 = 0 },
        gradient = Styles.Ability.maliceDiamondGradient,

        gui.Panel{
            classes = {"costInnerDiamond", "malice"},
            interactable = false,
        },
    }
end

--What each pool IS, over and above the change history the cell already
--shows on hover: a player meeting the strip for the first time gets told
--what the number is for. The hero token copy is the character panel's own
--tooltip (MCDMCharacterPanel HERO_TOKEN_TOOLTIP), kept word for word so the
--two never drift apart.
local POOL_TITLE = {
    malice = "Malice",
    herotokens = "Hero Tokens",
    intelligence = "Intelligence",
}

local POOL_EXPLANATION = {
    malice = [==[**Malice**

This is a power used by Monsters to charge their most powerful abilities. Beware that it will be used against you in battle!]==],

    herotokens = [==[**Hero Tokens**
* You can spend a hero token to gain two surges.
* You can spend a hero token when you fail a saving throw to succeed instead.
* You can reroll the result of a test. You must use the new result.
* You can spend 2 hero tokens to regain Stamina equal to your Recovery value without spending a Recovery.]==],

    intelligence = [==[**Intelligence**

The amount of awareness you have of what you are up against. It can be used at the start of a fight to control how much you know about the encounter.

Each hero keeps the Intelligence they earned (shown on their card), and each player spends their own heroes' Intelligence. This is the party's total.]==],
}

local POOL_TOOLTIP_WIDTH = 420

--One tooltip card: the explanation, then the pool's change history under it
--when there is any. The history cannot simply go in gui.StatsHistoryTooltip's
--own `text` argument -- that is a bare auto-width label, so a paragraph handed
--to it runs off the screen in a single line -- and the panel it returns paints
--no background of its own here, so the card's chrome is this panel's.
local function CreatePoolTooltip(kind, description)
    --- @type Panel[]
    local children = {
        gui.Label{
            markdown = true,
            text = POOL_EXPLANATION[kind],
            width = "auto",
            height = "auto",
            maxWidth = POOL_TOOLTIP_WIDTH,
            fontSize = 20,
            color = "#ffffff",
        },
    }

    local entries = PoolHistory(kind)
    if entries ~= nil and #entries > 0 then
        children[#children+1] = gui.StatsHistoryTooltip{
            description = description,
            entries = entries,
        }
    end

    --the standard tooltip chrome (CreateTooltipPanel's own styling), so a
    --pool tooltip looks like every other tooltip in the game.
    return gui.Panel{
        bgimage = "panels/square.png",
        bgcolor = "#000000ff",
        border = 1,
        borderColor = "#000000ff",
        cornerRadius = 10,
        hpad = 20,
        vpad = 14,
        width = "auto",
        height = "auto",
        flow = "vertical",
        halign = "center",
        valign = "bottom",
        children = children,
    }
end

local function CreatePoolCell(kind)
    local icon
    if kind == "malice" then
        icon = CreateMaliceDiamond()
    elseif kind == "intelligence" then
        icon = gui.Panel{
            classes = {"eotwPoolIcon", "intelligence"},
            bgimage = "phosphor/brain.png",
            interactable = false,
        }
    else
        icon = gui.Panel{
            classes = {"eotwPoolIcon"},
            bgimage = "drawsteel/hero-token.png",
            interactable = false,
        }
    end

    local value = gui.Label{
        classes = {"eotwPoolValue"},
        text = "0",
        interactable = false,
        data = { value = nil },
        refreshPools = function(element)
            local n = PoolValue(kind)
            if n ~= element.data.value then
                element.data.value = n
                element.text = string.format("%d", n)
            end
        end,
    }

    local description = POOL_TITLE[kind]

    --The blink: a white rectangle over the cell, invisible until the stage is
    --explaining this pool. It floats, so it frames the cell without taking
    --part in its layout, and it fades in and out on the shared blink clock so
    --it pulses in step with the callout that sent the party looking.
    local highlight = gui.Panel{
        floating = true,
        interactable = false,
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        bgimage = "panels/square.png",
        bgcolor = "#00000000",
        border = 2,
        borderColor = "#ffffffff",
        cornerRadius = 6,
        opacity = 0,
        --selfStyle is write-mostly here: reading back a key the style never
        --set raises ("Error indexing userdata"), so the last value we wrote
        --is kept in data and the think only writes when it changes.
        data = { blinking = false, opacity = 0 },
        blinkPool = function(element, feature)
            element.data.blinking = (feature == kind)
        end,
        thinkTime = 0.05,
        think = function(element)
            local alpha = 0
            if element.data.blinking then
                pcall(function() alpha = EncounterMontage.FeatureBlinkAlpha() end)
            end
            if alpha ~= element.data.opacity then
                element.data.opacity = alpha
                element.selfStyle.opacity = alpha
            end
        end,
    }

    return gui.Panel{
        classes = {"eotwPoolCell"},
        data = { kind = kind },
        --a panel with no bgimage is not hit-tested, so the cell needs a
        --(fully transparent) one of its own or the pointer sails past it to
        --the strip behind and neither the hover tint nor the tooltip fires.
        bgimage = "panels/square.png",
        bgcolor = "#00000000",
        --the diamond is rotated, so give it a square slot of its own to
        --spin in rather than letting the flow measure its unrotated box.
        gui.Panel{
            width = 26,
            height = 26,
            halign = "left",
            valign = "center",
            interactable = false,
            icon,
        },
        value,
        highlight,

        hover = function(element)
            element.tooltip = CreatePoolTooltip(kind, description)
        end,
    }
end

local function CreateEncounterPoolsPanel()
    local cells = {
        CreatePoolCell("malice"),
        CreatePoolCell("herotokens"),
        CreatePoolCell("intelligence"),
    }
    --the strip grows a cell wide when the week has an Intelligence pool, so
    --three pools are never squeezed into two pools' worth of strip.
    local m_cellCount = nil
    local strip

    local m_announced = nil

    local function RefreshLayout()
        local intelligence = IntelligenceUnlocked()
        cells[3]:SetClass("collapsed", not intelligence)
        --the blink follows whatever the stage is explaining; nil turns every
        --cell's rectangle off again.
        local announced = AnnouncedFeature()
        if announced ~= m_announced then
            m_announced = announced
            strip:FireEventTree("blinkPool", announced)
        end
        local count = cond(intelligence, 3, 2)
        if count ~= m_cellCount then
            m_cellCount = count
            strip.selfStyle.width = POOL_CELL_WIDTH * count
            for _, cell in ipairs(cells) do
                cell.selfStyle.width = string.format("%.4f%%", 100 / count)
            end
        end
    end

    strip = gui.Panel{
        id = "eotwEncounterPools",
        classes = {"eotwPoolsStrip"},
        --a plain panel paints no background without a bgimage.
        bgimage = "panels/square.png",
        width = CARD_WIDTH,
        height = POOLS_HEIGHT,
        flow = "horizontal",
        halign = "right",
        valign = "top",
        bmargin = POOLS_GAP,

        styles = ThemeEngine.MergeTokens{
            {
                selectors = {"eotwPoolsStrip"},
                bgcolor = "#000000c0",
                border = 1,
                borderColor = "#000000cc",
                cornerRadius = 8,
            },
            {
                selectors = {"eotwPoolCell"},
                width = "50%",
                height = "100%",
                --padding inside the 50%, not on top of it (two cells must
                --fit the strip exactly).
                borderBox = true,
                flow = "horizontal",
                halign = "left",
                valign = "center",
                hpad = 8,
                transitionTime = 0.15,
            },
            {
                selectors = {"eotwPoolCell", "hover"},
                brightness = 1.3,
            },
            {
                selectors = {"eotwPoolIcon"},
                width = 20,
                height = 20,
                halign = "center",
                valign = "center",
                bgcolor = "white",
            },
            {
                selectors = {"eotwPoolValue"},
                fontSize = 16,
                bold = true,
                color = "#ffffff",
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
                lmargin = 4,
            },
        },

        children = cells,

        create = function(element)
            RefreshLayout()
            element:FireEventTree("refreshPools")
        end,

        monitorGame = CharacterResource.GlobalResourcePath(),
        refreshGame = function(element)
            RefreshLayout()
            element:FireEventTree("refreshPools")
        end,

        --Four times a second, not once: this panel monitors the global
        --RESOURCE document, so nothing here fires when the script document
        --changes -- and Intelligence, the feature gate and the unlock blink
        --all live there. A tick is a handful of table reads.
        thinkTime = 0.25,
        think = function(element)
            if mod.unloaded then
                element:DestroySelf()
                return
            end
            RefreshLayout()
            element:FireEventTree("refreshPools")
        end,
    }

    return strip
end

--The whole right-rail widget: the pools strip above the hero roster. Both
--pack against the right edge; the roster's own fit-to-screen shrink
--pivots on its top-right corner so the strip above it is untouched.
local function CreateRightRailPanel()
    local roster = CreateHeroRosterPanel()

    return gui.Panel{
        id = "eotwRightRail",
        width = "auto",
        height = "auto",
        flow = "vertical",
        halign = "right",
        valign = "top",
        CreateEncounterPoolsPanel(),
        roster,

        --The hero roster is combat-only (user direction 2026-09-18):
        --while a montage beat is on screen the stage draws its own hero
        --cards along the bottom, so the side column would just duplicate
        --them. The pools strip above stays up either way -- it carries
        --malice and the party's hero tokens, which the stage does not
        --show. The toggle lives here, on a panel that is never collapsed
        --itself, so it keeps ticking while the roster is down.
        thinkTime = 0.5,
        think = function(element)
            local montagePresented = false
            pcall(function()
                montagePresented = EncounterMontage.IsPresented()
            end)
            roster:SetClass("collapsed", montagePresented)
        end,
    }
end

--- Kept rail buttons (bottom-left corner) -----------------------------------

local RAIL_BUTTON_SIZE = 40

--A rail-style button for one registered dockable panel: the standard
--iconRailButton look (the custom rail wrapper carries IconRailStyles), the
--panel's registered icon, its unread badge, the active underline, and the
--same open path the real rail button uses. Returns nil if the panel is
--not registered.
local function CreatePanelButton(panelName)
    local reg = nil
    pcall(function() reg = DockablePanel.GetRegistration(panelName) end)
    if reg == nil then
        return nil
    end
    local panelKey = string.lower(panelName)

    --unread badge: a 1x1 anchor on the button's top-right corner the
    --badge centers on, refreshed on the wrapper's refreshRail cadence --
    --the same recipe as the real rail button's new-content marker.
    local badge = nil
    if reg.hasNewContent ~= nil then
        local m_shownCount = nil
        badge = gui.Panel{
            floating = true,
            halign = "left",
            valign = "top",
            x = RAIL_BUTTON_SIZE - 3,
            y = 2,
            width = 1,
            height = 1,
            flow = "none",
            interactable = false,
            refreshRail = function(element)
                local shown = false
                pcall(function() shown = PanelDocument.IsPanelActive(panelKey) end)
                if shown and reg.markContentSeen ~= nil then
                    pcall(reg.markContentSeen)
                end
                local count = nil
                local hasNew = false
                pcall(function() hasNew = reg.hasNewContent() end)
                if (not shown) and hasNew then
                    count = 1
                    if reg.newContentCount ~= nil then
                        pcall(function() count = reg.newContentCount() or 1 end)
                    end
                    if count < 1 then
                        count = 1
                    end
                end
                if count == m_shownCount then
                    return
                end
                m_shownCount = count
                if count == nil then
                    element.children = {}
                else
                    element.children = {
                        gui.NewContentAlert{
                            count = count,
                            size = 16,
                            halign = "center",
                            valign = "center",
                            x = 0,
                            y = 0,
                            interactable = false,
                        },
                    }
                end
            end,
        }
    end

    return gui.Panel{
        classes = {"iconRailButton"},
        width = RAIL_BUTTON_SIZE,
        height = RAIL_BUTTON_SIZE,
        vmargin = 4,
        bgimage = "panels/square.png",
        blurBackground = true,
        swallowPress = true,

        --the rail-button identity shared chrome looks for. No slot: a
        --provider widget is not on the rail's slot grid. The chat speech
        --bubble finds its anchor this way (DocumentSystem's
        --FindChatRailButton), so a message arriving while chat is closed
        --bubbles off THIS button during the takeover, montage included.
        data = { key = panelKey },

        press = function(element)
            audio.FireSoundEvent("Mouse.Click")
            DockablePanel.LaunchPanelByName(panelName, "toggle")
        end,

        hover = function(element)
            gui.Tooltip(panelName)(element)
        end,

        --lit state while the panel's window is up (the underline below
        --reveals on the "active" class, and the icon brightens).
        refreshRail = function(element)
            local shown = false
            pcall(function() shown = PanelDocument.IsPanelShown(panelKey) end)
            element:SetClass("active", shown)
        end,

        gui.Panel{
            classes = {"iconRailIcon"},
            bgimage = reg.icon,
            width = 20,
            height = 20,
            halign = "center",
            valign = "center",
            interactable = false,
        },

        gui.Panel{
            classes = {"iconRailActiveMark"},
            bgimage = true,
            width = 16,
            height = 2,
            halign = "center",
            valign = "bottom",
            y = -3,
            interactable = false,
        },

        badge,
    }
end

--The bottom-left corner strip: the Journal, Chat and Action Log buttons
--survive the takeover (user direction 2026-08-28 for chat/log,
--2026-08-30 for the journal) so players keep the encounter's briefing
--documents, chat, and the roll history. Journal sits ABOVE the other two
--(vertical flow, so first in the list is the topmost button).
local function CreateCornerButtonsPanel()
    local buttons = {}
    for _, name in ipairs({"Journal", "Chat", "Action Log"}) do
        buttons[#buttons+1] = CreatePanelButton(name)
    end
    if #buttons == 0 then
        return nil
    end
    return gui.Panel{
        id = "eotwCornerButtons",
        width = "auto",
        height = "auto",
        flow = "vertical",
        halign = "left",
        children = buttons,
    }
end

--- Exports -------------------------------------------------------------------

--Shared with the montage stage (EncounterMontageStage.lua), which shows the
--same hero cards along the bottom of the screen.
EncounterOfTheWeekHud = rawget(_G, "EncounterOfTheWeekHud") or {}
EncounterOfTheWeekHud.CreateHeroCard = CreateHeroCard
EncounterOfTheWeekHud.CreateAllyCard = CreateAllyCard
EncounterOfTheWeekHud.CreateStaminaBar = CreateStaminaBar
EncounterOfTheWeekHud.CreateMaliceDiamond = CreateMaliceDiamond
EncounterOfTheWeekHud.CreateEncounterPoolsPanel = CreateEncounterPoolsPanel
EncounterOfTheWeekHud.CollectHeroes = CollectHeroes
EncounterOfTheWeekHud.HeroCardRules = function()
    return g_heroCardRules
end

--- The custom-interface registration ----------------------------------------

--The EotW hero sheet, when this token's sheet should be it: a Hero, with the
--sheet's code loaded. Monsters and objects get nil (the normal sheet).
local function HeroSheetFor(token)
    local sheet = rawget(_G, "EotwHeroSheet")
    if sheet == nil or token == nil then
        return nil
    end
    local isHero = false
    pcall(function() isHero = token.properties ~= nil and token.properties:IsHero() end)
    if not isHero then
        return nil
    end
    return sheet
end

--Is the EotW interface up on this client: a real EotW game or an authoring
--test, unless the Director-UI escape hatch (or a --director debug window)
--restores the whole normal interface for debugging/manual recovery.
local function IsInterfaceActive()
    local eotw = rawget(_G, "EncounterOfTheWeekGame")
    if eotw == nil or not eotw.IsEotwGame() then
        return false
    end
    if eotw.ShowDirectorUI ~= nil then
        return not eotw.ShowDirectorUI()
    end
    return dmhub.GetSettingValue("eotw:showdirectorui") ~= true
end

--pcall: an older core codex without the hook just shows the normal hud.
pcall(function()
    GameHud.RegisterCustomInterface{
        id = "eotw",

        active = IsInterfaceActive,

        suppressRails = true,

        --the pools strip + roster hang off the RIGHT edge; the kept rail
        --buttons stay in the bottom-LEFT corner where the real rail's are.
        railPanel = function(side)
            if side == "right" then
                return CreateRightRailPanel()
            end
            return nil
        end,

        railBottomPanel = function(side)
            if side == "left" then
                return CreateCornerButtonsPanel()
            end
            return nil
        end,

        suppressTitlebarMenu = { ["Panels"] = true },

        --an authoring test's status and its END TEST button (EncounterTest
        --loads after this file, so it is looked up at call time).
        titlebarPanels = function()
            local test = rawget(_G, "EncounterTest")
            local eotw = rawget(_G, "EncounterOfTheWeekGame")
            if test == nil or eotw == nil or not eotw.IsTestPlayer() then
                return nil
            end
            return { test.CreateTitlebarItem() }
        end,

        --the players row's popout lists who is here and their heroes, and
        --lets the host hand a departed player's heroes to someone else
        --(EncounterPresence loads after this file: looked up at call time).
        playersPopout = function()
            local presence = rawget(_G, "EncounterPresence")
            if presence == nil then
                return nil
            end
            return presence.CreatePlayersPopout()
        end,

        --leaving or quitting asks whether the player will come back (Leave)
        --or gives the game up (Abandon Game).
        confirmExit = function(kind, proceed)
            local presence = rawget(_G, "EncounterPresence")
            if presence == nil then
                return false
            end
            return presence.ConfirmExit(kind, proceed)
        end,

        --the encounter's map is held maximized for the whole game, test
        --included: no restore, minimize or close, the same as a player whose
        --Director holds a shared map maximized (Tabletop.lua).
        forcedMap = function()
            return game.currentMapId
        end,

        suppressPanel = { ["Compendium"] = true },

        suppressSearchBucket = { ["compendium"] = true },

        --every hero's panel may be opened by anyone, read-only -- your own
        --included (strict rules: state changes go through the action bar
        --and the game's own flows, never sheet edits). Non-hero tokens
        --keep the normal rules.
        characterPanelAccess = function(token)
            local playerControlled = false
            pcall(function() playerControlled = token.playerControlled end)
            if playerControlled then
                return "view"
            end
            return nil
        end,

        --every route to a hero's full character sheet (c / i, the radial,
        --search, /opensheet...) opens the EotW hero sheet instead. Other
        --tokens (monsters, objects) keep the normal sheet.
        ownsSheet = function(token)
            return HeroSheetFor(token) ~= nil
        end,
        openSheet = function(token, tabid)
            local sheet = HeroSheetFor(token)
            if sheet == nil then
                return false
            end
            --c toggles: asked again for the Hero on show, it closes
            if sheet.IsShowing ~= nil and sheet.IsShowing(token.charid) then
                sheet.Close()
                return true
            end
            return sheet.Show{ charid = token.charid, context = "game" } ~= nil
        end,
    }
end)

--- About Encounter of the Week (Codex menu) ----------------------------------
--Codex > About Encounter of the Week, in any EotW game (an authoring test
--too): the mode's credits, then the encounter being played -- who wrote it
--(its module's author) and, when its map came from a map pack, who made the
--map (the pack's creator organization).

--The banner is the Town Gate's art (GATE_ART in Codex Titlescreen/
--EncounterOfTheWeek.lua), which that file tags as Czepeku's, so the banner
--carries the watermark their licence asks for.
local ABOUT_ART = "db5bcf88-00fc-4e0b-89c9-5ddb98d1a772"
local ABOUT_WIDTH = 720
local ABOUT_ART_HEIGHT = 240
local ABOUT_THUMB_WIDTH = 168
local ABOUT_THUMB_HEIGHT = 108

--The mode's credits, in order. Markup is TextMeshPro rich text.
local ABOUT_CREDITS = {
    "<b>Draw Steel</b> by MCDM",
    "<b>Encounter of the Week</b> concept and engineering by the Codex Development Team",
    "<b>Cartography</b> by Czepeku",
}

local ABOUT_STYLES = {
    {
        selectors = {"label", "eotwAboutTitle"},
        fontSize = 30,
        bold = true,
        color = "@fgStrong",
        width = "100%-48",
        height = "auto",
        halign = "center",
        textAlignment = "center",
    },
    {
        selectors = {"label", "eotwAboutCredit"},
        fontSize = 18,
        color = "@fg",
        width = "100%-24",
        height = "auto",
        halign = "center",
        textAlignment = "center",
        textWrap = true,
        vmargin = 5,
    },
    {
        selectors = {"label", "eotwAboutHeading"},
        fontSize = 22,
        bold = true,
        color = "@fgStrong",
        width = "100%",
        height = "auto",
        textWrap = true,
    },
    {
        selectors = {"label", "eotwAboutLine"},
        fontSize = 17,
        color = "@fg",
        width = "100%",
        height = "auto",
        textWrap = true,
        tmargin = 6,
    },
    {
        selectors = {"eotwAboutRule"},
        width = "100%-64",
        height = 1,
        halign = "center",
        bgimage = "panels/square.png",
        bgcolor = "@border",
        vmargin = 16,
    },
}

--Creator organization id -> display name, or false when the lookup failed.
--- @type table<string, string|false>
local g_aboutOrgNames = {}

--Calls back with an organization's display name, or nil when it has none
--or the lookup fails. Answers at once from the cache.
--- @param orgid nil|string
--- @param callback fun(name: nil|string)
local function AboutOrgName(orgid, callback)
    if orgid == nil or orgid == "" then
        callback(nil)
        return
    end
    local cached = g_aboutOrgNames[orgid]
    if cached ~= nil then
        callback(cached or nil)
        return
    end
    module.GetOrganizationInfo{
        orgid = orgid,
        success = function(info)
            local name = type(info) == "table" and info.displayName or nil
            if type(name) ~= "string" or name == "" then
                name = nil
            end
            g_aboutOrgNames[orgid] = name or false
            if not mod.unloaded then
                callback(name)
            end
        end,
        failure = function()
            g_aboutOrgNames[orgid] = false
            if not mod.unloaded then
                callback(nil)
            end
        end,
    }
end

--Calls back with the name of whoever published an encounter module: its
--creator organization's name, else the organization its author id names
--(author ids are often organization ids: "mcdm"), else the author id. nil
--when the module is not known here.
--- @param moduleid nil|string
--- @param callback fun(name: nil|string)
local function AboutEncounterAuthor(moduleid, callback)
    local info = moduleid ~= nil and module.GetModule(moduleid) or nil
    if info == nil then
        callback(nil)
        return
    end
    local org, authorid = nil, nil
    pcall(function() org = info.org end)
    pcall(function() authorid = info.authorid end)
    if authorid == "" then
        authorid = nil
    end
    if org == nil or org == "" then
        org = authorid
    end
    AboutOrgName(org, function(name)
        callback(name or authorid)
    end)
end

--The map pack a map was added from (its module fullid), or nil.
--- @param mapid string
--- @return nil|string
local function AboutMapPack(mapid)
    local pack = nil
    pcall(function()
        local source = game.GetMap(mapid).packSource
        if source ~= nil and type(source.pack) == "string" and source.pack ~= "" then
            pack = source.pack
        end
    end)
    return pack
end

--Calls back with the creator of a map that came from a map pack (the pack's
--creator organization's name), or nil for any other map. A map added before
--provenance was recorded is only recognised once the pack index has synced,
--so an unsynced index is synced first.
--- @param mapid string
--- @param callback fun(name: nil|string)
local function AboutMapCreator(mapid, callback)
    local function FromPack(pack)
        local org = nil
        for _,p in ipairs(mappacks.packs or {}) do
            if p.id == pack then
                org = p.org
            end
        end
        if org == nil or org == "" then
            pcall(function() org = module.GetModule(pack).org end)
        end
        AboutOrgName(org, callback)
    end

    local pack = AboutMapPack(mapid)
    if pack ~= nil then
        FromPack(pack)
        return
    end
    if mappacks.synced then
        callback(nil)
        return
    end
    mappacks.Sync{
        success = function()
            if mod.unloaded then
                return
            end
            local synced = AboutMapPack(mapid)
            if synced == nil then
                callback(nil)
            else
                FromPack(synced)
            end
        end,
        error = function()
            if not mod.unloaded then
                callback(nil)
            end
        end,
    }
end

local m_aboutDialog = nil

local function CloseAbout()
    if m_aboutDialog ~= nil and m_aboutDialog.valid then
        local hud = rawget(_G, "gamehud")
        if hud ~= nil then
            hud:CloseModal()
        end
    end
    m_aboutDialog = nil
end

--The "About <encounter>" part of the dialog: heading, author and map
--creator (filled in as their lookups come back), beside the map's thumbnail
--when it has one.
--- @param info {title: string, mapid: string, moduleid: nil|string}
--- @return Panel
local function AboutEncounterSection(info)
    --hidden until its lookup comes back with a name.
    local function PendingLine()
        return gui.Label{
            classes = {"eotwAboutLine", "collapsed"},
            text = "",
            fill = function(element, text)
                element.text = text
                element:SetClass("collapsed", false)
            end,
        }
    end

    local authorLabel = PendingLine()
    local mapLabel = PendingLine()

    local function Fill(label, prefix)
        return function(name)
            if name ~= nil and label.valid then
                label:FireEvent("fill", string.format("%s <b>%s</b>", prefix, name))
            end
        end
    end
    AboutEncounterAuthor(info.moduleid, Fill(authorLabel, "Written by"))
    AboutMapCreator(info.mapid, Fill(mapLabel, "Map by"))

    local thumb = nil
    pcall(function() thumb = game.GetMap(info.mapid).thumbnailImage end)
    local thumbPanel = nil
    if type(thumb) == "string" and thumb ~= "" then
        thumbPanel = gui.Panel{
            width = ABOUT_THUMB_WIDTH,
            height = ABOUT_THUMB_HEIGHT,
            valign = "top",
            rmargin = 20,
            flow = "none",
            CreatorCredit.Backdrop{
                width = ABOUT_THUMB_WIDTH,
                height = ABOUT_THUMB_HEIGHT,
                image = thumb,
                badge = false,
            },
        }
    end

    return gui.Panel{
        width = "100%-64",
        height = "auto",
        halign = "center",
        flow = "horizontal",
        thumbPanel,
        gui.Panel{
            width = cond(thumbPanel ~= nil, string.format("100%%-%d", ABOUT_THUMB_WIDTH + 20), "100%"),
            height = "auto",
            valign = "center",
            flow = "vertical",
            gui.Label{
                classes = {"eotwAboutHeading"},
                text = string.format("About %s", info.title),
            },
            authorLabel,
            mapLabel,
        },
    }
end

--Opens the About Encounter of the Week dialog (or leaves it up if it is).
function EncounterOfTheWeekHud.ShowAbout()
    local hud = rawget(_G, "gamehud")
    if hud == nil then
        return
    end
    if m_aboutDialog ~= nil and m_aboutDialog.valid then
        return
    end

    local info = nil
    local eotw = rawget(_G, "EncounterOfTheWeekGame")
    if eotw ~= nil and eotw.EncounterInfo ~= nil then
        pcall(function() info = eotw.EncounterInfo() end)
    end

    local credits = {}
    for _,text in ipairs(ABOUT_CREDITS) do
        credits[#credits+1] = gui.Label{
            classes = {"eotwAboutCredit"},
            text = text,
        }
    end

    local encounterChildren = {}
    if info ~= nil then
        encounterChildren[#encounterChildren+1] = gui.Panel{ classes = {"eotwAboutRule"} }
        encounterChildren[#encounterChildren+1] = AboutEncounterSection(info)
    end

    m_aboutDialog = gui.Panel{
        classes = {"framedPanel"},
        styles = ThemeEngine.MergeStyles(ABOUT_STYLES),
        width = ABOUT_WIDTH,
        height = "auto",
        flow = "vertical",
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        captureEscape = true,
        escape = function(element)
            CloseAbout()
        end,

        --the banner: the art, cover-fitted, with Czepeku's watermark.
        gui.Panel{
            width = ABOUT_WIDTH,
            height = ABOUT_ART_HEIGHT,
            halign = "center",
            flow = "none",
            CreatorCredit.Backdrop{
                width = ABOUT_WIDTH,
                height = ABOUT_ART_HEIGHT,
                image = ABOUT_ART,
                creator = "czepeku",
                badge = { hmargin = 16, vmargin = 12 },
            },
        },

        gui.Label{
            classes = {"eotwAboutTitle"},
            text = "About Encounter of the Week",
            tmargin = 18,
            bmargin = 12,
        },

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            children = credits,
        },

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            children = encounterChildren,
        },

        gui.Button{
            classes = {"sizeL"},
            text = "Close",
            halign = "center",
            tmargin = 22,
            bmargin = 18,
            click = function()
                CloseAbout()
            end,
        },
    }
    hud:ShowModal(m_aboutDialog)
end

Commands.Register{
    name = "About Encounter of the Week",
    identifier = "eotwabout",
    icon = "phosphor/info.png",
    menu = "codex",
    --its own group, so the menu sets it apart from the rows above it.
    group = "zzeotwabout",
    filtered = function()
        local eotw = rawget(_G, "EncounterOfTheWeekGame")
        return eotw == nil or not eotw.IsEotwGame()
    end,
    execute = function()
        EncounterOfTheWeekHud.ShowAbout()
    end,
}
