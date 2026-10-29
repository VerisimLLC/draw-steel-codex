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

local T = UIText.T

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
--party's shared Hero Tokens. Malice is read-only (the Monster AI spends
--it); on a hero's turn its player can click Hero Tokens to spend them (see
--CreatePoolCell). Hovering a cell shows the pool's change history. Both pools live in the
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
    malice = T("hud.pool.malice.title"),
    herotokens = T("hud.pool.herotokens.title"),
    intelligence = T("hud.pool.intelligence.title"),
}

local POOL_EXPLANATION = {
    malice = T("hud.pool.malice.explanation"),

    herotokens = T("hud.pool.herotokens.explanation"),

    intelligence = T("hud.pool.intelligence.explanation"),
}

local POOL_TOOLTIP_WIDTH = 420

--One tooltip card: the explanation, then the pool's change history under it
--when there is any. The history cannot simply go in gui.StatsHistoryTooltip's
--own `text` argument -- that is a bare auto-width label, so a paragraph handed
--to it runs off the screen in a single line -- and the panel it returns paints
--no background of its own here, so the card's chrome is this panel's.
local function CreatePoolTooltip(kind, description, hint)
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

    --a call to action under the explanation (e.g. "click to spend").
    if hint ~= nil then
        children[#children+1] = gui.Label{
            text = hint,
            width = "auto",
            height = "auto",
            maxWidth = POOL_TOOLTIP_WIDTH,
            fontSize = 18,
            italics = true,
            color = "#e0b84c",
            tmargin = 8,
        }
    end

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

--The hero the local player may spend Hero Tokens for from the pool cell: one
--they control whose turn it is. nil between turns and on anyone else's turn.
--- @return CharacterToken|nil
local function SpendingHero()
    local q = dmhub.initiativeQueue
    if q == nil or q.hidden then
        return nil
    end
    for _, tok in ipairs(dmhub.allTokens) do
        local ok = false
        pcall(function()
            ok = tok.canControl and tok.properties:IsHero() and tok.properties:IsOurTurn()
        end)
        if ok then
            return tok
        end
    end
    return nil
end

--Whether the hero can buy anything from the pool right now. Under the strict
--rules EotW forces, HeroTokenSpendOptions lists only what is affordable and
--usable; the available check also covers a Director testing with them off.
--- @param hero CharacterToken|nil
--- @return boolean
local function CanSpendHeroTokens(hero)
    if hero == nil then
        return false
    end
    for _, option in ipairs(CharacterResource.HeroTokenSpendOptions(hero)) do
        if option.available then
            return true
        end
    end
    return false
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
        --the spend menu hangs off the cell, not wherever the pointer was.
        popupPositioning = "panel",
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

        --Hero Tokens only: on the local player's hero's turn, while they can
        --afford something, the cell is outlined and a click opens the spend
        --menu (CharacterResource.HeroTokenSpendOptions decides what is on it).
        --Rides the strip's refreshPools tick, so it follows the turn and pool.
        refreshPools = function(element)
            if kind ~= "herotokens" then
                return
            end
            local spendable = false
            pcall(function() spendable = CanSpendHeroTokens(SpendingHero()) end)
            if spendable ~= element:HasClass("spendable") then
                element:SetClass("spendable", spendable)
                if not spendable then
                    element.popup = nil
                end
            end
        end,

        press = function(element)
            if kind ~= "herotokens" or not element:HasClass("spendable") then
                return
            end
            local entries = CharacterResource.HeroTokenSpendMenuEntries(SpendingHero(), function()
                element.popup = nil
            end)
            --the hover tooltip would sit on top of the menu.
            element.tooltip = nil
            element.popup = gui.ContextMenu{
                entries = entries,
                halign = "left",
                valign = "bottom",
            }
        end,

        hover = function(element)
            local hint = nil
            if element:HasClass("spendable") then
                hint = T("hud.pool.herotokens.spend_hint")
            end
            element.tooltip = CreatePoolTooltip(kind, description, hint)
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
            --the Hero Tokens cell when a click opens the spend menu.
            {
                selectors = {"eotwPoolCell", "spendable"},
                border = 1,
                borderColor = "#e0b84cff",
                cornerRadius = 6,
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

--Defined with the map creator watermark, below; the rail's think keeps it up.
--- @type fun(hidden: boolean)
local UpdateMapWatermark

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
            --the montage stage covers the map; its scenes credit their own art.
            UpdateMapWatermark(montagePresented)
        end,
        --the interface is going away (e.g. the Director-UI hatch).
        destroy = function(element)
            UpdateMapWatermark(true)
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
            --a folder window (Measuring Tool + Whiteboard share one) sitting
            --on another member's tab: switch to this tab rather than closing
            --the window, as the real rail button does.
            local operation = "toggle"
            pcall(function()
                if PanelDocument.IsPanelShown(panelKey) and not PanelDocument.IsPanelActive(panelKey)
                    and not PanelDocument.IsPoppedOut(panelKey) then
                    operation = "show"
                end
            end)
            DockablePanel.LaunchPanelByName(panelName, operation)
        end,

        hover = function(element)
            gui.Tooltip(panelName)(element)
        end,

        --lit state while the panel's window is up (the underline below
        --reveals on the "active" class, and the icon brightens).
        refreshRail = function(element)
            --IsPanelActive, not IsPanelShown: in a folder window only the
            --tab on screen lights, not every member filed in it.
            local shown = false
            pcall(function()
                shown = PanelDocument.IsPanelActive(panelKey) or PanelDocument.IsPoppedOut(panelKey)
            end)
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

--- Encounter Rules (bottom-left corner) --------------------------------------

--An encounter may ship an "Encounter Rules" journal document (filed in its
--map's journal folder; see EncounterMontage.FindRulesDocument). Once combat
--begins a book button joins the corner strip and opens it in a read-only
--reading window.
local RULES_ICON = "phosphor/book-bookmark.png"
local RULES_WINDOW_WIDTH = 760
local RULES_WINDOW_HEIGHT = 860

---@type Panel?
local m_rulesDialog = nil
--the read-only copy last shown, so a reopened window keeps where the
--player dragged it (_tmp_location lives on the document).
---@type MarkdownDocument?
local m_rulesCopy = nil
--documents opened this session: the button's "new" badge goes once read.
local m_rulesSeen = {}
--the live corner button, if any (a rail rebuild replaces it).
---@type Panel?
local m_rulesButton = nil

--The Encounter Rules document to offer now, or nil: only once combat has
--begun, and only when the map (or this series part) has one.
local function CurrentRulesDocument()
    local montage = rawget(_G, "EncounterMontage")
    local eotw = rawget(_G, "EncounterOfTheWeekGame")
    if montage == nil or eotw == nil or montage.FindRulesDocument == nil or eotw.CombatStarted == nil then
        return nil
    end
    local doc = nil
    pcall(function()
        if eotw.CombatStarted() then
            doc = montage.FindRulesDocument()
        end
    end)
    return doc
end

local function IsRulesOpen()
    return m_rulesDialog ~= nil and m_rulesDialog.valid
end

local function CloseRules()
    local dialog = m_rulesDialog
    if dialog ~= nil and dialog.valid then
        dialog:DestroySelf()
    end
    m_rulesDialog = nil
end

local function ShowRules(doc)
    CloseRules()
    m_rulesSeen[doc.id] = true
    --a local read-only copy: nothing in the window can edit or upload the
    --encounter's document, even for a Director running an authoring test
    --or the author playing their own module.
    local copy = DeepCopy(doc)
    copy.readonly = true
    if m_rulesCopy ~= nil and m_rulesCopy.id == doc.id and m_rulesCopy:has_key("_tmp_location") then
        copy._tmp_location = m_rulesCopy._tmp_location
    end
    m_rulesCopy = copy
    m_rulesDialog = copy:PresentDocument{
        --no editing, presenting or journal breadcrumb; the reader keeps
        --the close button.
        presentationMode = true,
        presentationAllowClose = true,
        width = RULES_WINDOW_WIDTH,
        height = RULES_WINDOW_HEIGHT,
    }
    GameHud.instance.documentsPanel:AddChild(m_rulesDialog)
    --the rail-mode Font Size zoom needs the window attached.
    m_rulesDialog:FireEvent("setWindowScale")
end

local function CreateRulesButton()
    local m_doc = nil
    local m_badgeShown = false

    local badge = gui.Panel{
        floating = true,
        halign = "left",
        valign = "top",
        x = RAIL_BUTTON_SIZE - 3,
        y = 2,
        width = 1,
        height = 1,
        flow = "none",
        interactable = false,
    }

    --shows/hides the button, lights it while the window is up, and keeps
    --the "new" badge until the rules are first read.
    local function Sync(button)
        local doc = CurrentRulesDocument()
        m_doc = doc
        button:SetClass("collapsed", doc == nil)
        if doc == nil then
            --combat reset (an authoring test restarted or ended): the
            --window goes with the button.
            CloseRules()
            return
        end
        button:SetClass("active", IsRulesOpen())
        local showBadge = not m_rulesSeen[doc.id]
        if showBadge ~= m_badgeShown then
            m_badgeShown = showBadge
            if showBadge then
                badge.children = {
                    gui.NewContentAlert{
                        count = 1,
                        size = 16,
                        halign = "center",
                        valign = "center",
                        x = 0,
                        y = 0,
                        interactable = false,
                    },
                }
            else
                badge.children = {}
            end
        end
    end

    local button
    button = gui.Panel{
        classes = {"iconRailButton", "collapsed"},
        width = RAIL_BUTTON_SIZE,
        height = RAIL_BUTTON_SIZE,
        vmargin = 4,
        bgimage = "panels/square.png",
        blurBackground = true,
        swallowPress = true,

        press = function(element)
            audio.FireSoundEvent("Mouse.Click")
            if IsRulesOpen() then
                CloseRules()
            elseif m_doc ~= nil then
                ShowRules(m_doc)
            end
            Sync(element)
        end,

        hover = function(element)
            gui.Tooltip(T("hud.rules_button.tooltip"))(element)
        end,

        gui.Panel{
            classes = {"iconRailIcon"},
            bgimage = RULES_ICON,
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

    --the thinking wrapper never collapses (a collapsed panel's think
    --never runs); it shrinks to nothing while the button is collapsed.
    return gui.Panel{
        width = "auto",
        height = "auto",
        halign = "center",
        flow = "vertical",
        thinkTime = 0.25,
        create = function(element)
            m_rulesButton = element
            Sync(button)
        end,
        think = function(element)
            Sync(button)
        end,
        destroy = function(element)
            --the interface going away (End Test, the Director-UI hatch)
            --takes the window with it; a rail rebuild that remounts the
            --button within a moment keeps it.
            dmhub.Schedule(0.5, function()
                if mod.unloaded or m_rulesButton == nil or not m_rulesButton.valid then
                    CloseRules()
                end
            end)
        end,
        button,
    }
end

--The bottom-left corner strip: the Journal, Chat and Action Log buttons
--survive the takeover (user direction 2026-08-28 for chat/log,
--2026-08-30 for the journal) so players keep the encounter's briefing
--documents, chat, and the roll history. Journal sits ABOVE the other two
--(vertical flow, so first in the list is the topmost button).
--The map tools (playtest 2026-10-19 N4) sit above those, behind a short
--rule: the EotW takeover hides the map rail that normally carries them.
--The Encounter Rules book sits directly above Journal, collapsed until
--combat begins in an encounter that has rules.
local function CreateCornerButtonsPanel()
    local buttons = {}
    for _, name in ipairs({"Measuring Tool", "Whiteboard"}) do
        buttons[#buttons+1] = CreatePanelButton(name)
    end
    local toolCount = #buttons
    buttons[#buttons+1] = CreateRulesButton()
    for _, name in ipairs({"Journal", "Chat", "Action Log"}) do
        buttons[#buttons+1] = CreatePanelButton(name)
    end
    if #buttons == 0 then
        return nil
    end
    if toolCount > 0 and #buttons > toolCount then
        table.insert(buttons, toolCount + 1, gui.Panel{
            classes = {"iconRailMapDivider"},
            bgimage = true,
            interactable = false,
            width = RAIL_BUTTON_SIZE - 12,
            height = 2,
            halign = "center",
            vmargin = 6,
        })
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

--The mode's credits, in order: the line (TextMeshPro rich text) given the
--name as it is shown, the name, and optionally a site the name links to.
--- @type {line: (fun(name: string): string), name: string, url: nil|string}[]
local ABOUT_CREDITS = {
    { line = function(name) return T("hud.about.credit.draw_steel", { name = name }) end, name = "MCDM" },
    { line = function(name) return T("hud.about.credit.eotw", { name = name }) end, name = T("hud.about.credit.eotw_name") },
    { line = function(name) return T("hud.about.credit.cartography", { name = name }) end, name = "Czepeku", url = "https://czepeku.com" },
}

--Map packs whose maps are credited to someone other than the pack's
--publishing organization: pack module fullid -> {name, url}.
--- @type table<string, {name: string, url: nil|string}>
local ABOUT_MAP_PACK_CREATORS = {
    ["mcdm-encountermaps"] = { name = "MAD Cartographer", url = "https://themad.network/the-mad-cartographer" },
}

--A name as rich text, bold if asked, and when it has a url a link: accent
--colored and underlined (some schemes' accent is close to the body text),
--which an AboutLinkLabel opens on press.
--- @param name string
--- @param url nil|string
--- @param bold nil|boolean
--- @return string
local function AboutName(name, url, bold)
    if bold then
        name = string.format("<b>%s</b>", name)
    end
    if url == nil or url == "" then
        return name
    end
    return ThemeEngine.ResolveTokens(string.format("<color=@accent><u><link=%s>%s</link></u></color>", url, name))
end

--A gui.Label whose <link=url> spans open their url when pressed.
--- @param options table
--- @return Panel
local function AboutLinkLabel(options)
    options.links = true
    options.press = function(element)
        if element.linkHovered ~= nil then
            dmhub.OpenURL(element.linkHovered)
        end
    end
    return gui.Label(options)
end

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

--- @alias AboutCredit {name: string, url: nil|string}

--Creator organization id -> {name, url}, or false when the lookup failed.
--- @type table<string, AboutCredit|false>
local g_aboutOrgNames = {}

--Calls back with an organization's display name and website, or nil when
--it has no name or the lookup fails. Answers at once from the cache.
--- @param orgid nil|string
--- @param callback fun(credit: nil|AboutCredit)
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
            local credit = nil
            local name = type(info) == "table" and info.displayName or nil
            if type(name) == "string" and name ~= "" then
                local url = info.url
                credit = { name = name, url = cond(type(url) == "string" and url ~= "", url, nil) }
            end
            g_aboutOrgNames[orgid] = credit or false
            if not mod.unloaded then
                callback(credit)
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
--- @param callback fun(credit: nil|AboutCredit)
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
    AboutOrgName(org, function(credit)
        if credit == nil and authorid ~= nil then
            credit = { name = authorid }
        end
        callback(credit)
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

--The creator organization that publishes a map pack, or nil.
--- @param pack string
--- @return nil|string
local function MapPackOrg(pack)
    local org = nil
    for _,p in ipairs(mappacks.packs or {}) do
        if p.id == pack then
            org = p.org
        end
    end
    if org == nil or org == "" then
        pcall(function() org = module.GetModule(pack).org end)
    end
    if org == "" then
        return nil
    end
    return org
end

--Calls back with the map pack a map came from, or nil. A map added before
--provenance was recorded is only recognised once the pack index has synced,
--so an unsynced index is synced first.
--- @param mapid string
--- @param callback fun(pack: nil|string)
local function MapPackOf(mapid, callback)
    local pack = AboutMapPack(mapid)
    if pack ~= nil or mappacks.synced then
        callback(pack)
        return
    end
    mappacks.Sync{
        success = function()
            if not mod.unloaded then
                callback(AboutMapPack(mapid))
            end
        end,
        error = function()
            if not mod.unloaded then
                callback(nil)
            end
        end,
    }
end

--Calls back with the creator of a map that came from a map pack (the pack's
--entry in ABOUT_MAP_PACK_CREATORS, else its creator organization), or nil
--for any other map.
--- @param mapid string
--- @param callback fun(credit: nil|AboutCredit)
local function AboutMapCreator(mapid, callback)
    MapPackOf(mapid, function(pack)
        if pack == nil then
            callback(nil)
        elseif ABOUT_MAP_PACK_CREATORS[pack] ~= nil then
            callback(ABOUT_MAP_PACK_CREATORS[pack])
        else
            AboutOrgName(MapPackOrg(pack), callback)
        end
    end)
end

--- Map creator watermark -----------------------------------------------------

--(user direction 2026-10-19) While a map from a map pack is on screen, its
--creator's logo sits in the bottom-right corner of the map window; clicking
--it opens their Patreon (CreatorCredit.ForOrganization). EotW games only: the
--whole interface, this included, is up only there (IsInterfaceActive).

--Creator organizations whose maps carry no watermark: MCDM's own.
local MAP_WATERMARK_EXEMPT_ORGS = { mcdm = true }

local MAP_WATERMARK_HEIGHT = 36

--mapid -> its watermark credit, false for none, or true while looking it up.
--- @type table<string, CreatorCreditInfo|boolean>
local g_mapWatermarkCredits = {}

--The badge on screen, and the map window overlay and creator it is for.
local m_mapWatermark = nil
local m_mapWatermarkHost = nil
local m_mapWatermarkCreator = nil

--The watermark credit for a map: nil when it has none, or until its lookup
--(started here on first ask) comes back.
--- @param mapid string
--- @return nil|CreatorCreditInfo
local function MapWatermarkCredit(mapid)
    local cached = g_mapWatermarkCredits[mapid]
    if type(cached) == "table" then
        return cached
    end
    if cached ~= nil then
        return nil
    end
    g_mapWatermarkCredits[mapid] = true
    MapPackOf(mapid, function(pack)
        local org = pack ~= nil and MapPackOrg(pack) or nil
        if org == nil or MAP_WATERMARK_EXEMPT_ORGS[org] then
            g_mapWatermarkCredits[mapid] = false
            return
        end
        CreatorCredit.ForOrganization(org, function(info)
            g_mapWatermarkCredits[mapid] = info or false
        end)
    end)
    return nil
end

local function RemoveMapWatermark()
    if m_mapWatermark ~= nil and m_mapWatermark.valid then
        m_mapWatermark:DestroySelf()
    end
    m_mapWatermark = nil
    m_mapWatermarkHost = nil
    m_mapWatermarkCreator = nil
end

--Keeps the watermark on the live map window: added, moved to a new window,
--or taken down as the map, its window or the montage changes. Called from
--the right rail's think (CreateRightRailPanel), and with hidden = true when
--the rail goes away.
--- @param hidden boolean
UpdateMapWatermark = function(hidden)
    --- @type nil|Panel
    local host = nil
    local credit = nil
    if not hidden then
        pcall(function() host = Tabletop.MapOverlayHost() end)
        local mapid = game.currentMapId
        if host ~= nil and mapid ~= nil then
            credit = MapWatermarkCredit(mapid)
        end
    end
    if host == nil or credit == nil then
        RemoveMapWatermark()
        return
    end
    if m_mapWatermark ~= nil and m_mapWatermark.valid and m_mapWatermarkHost == host and m_mapWatermarkCreator == credit.id then
        return
    end
    RemoveMapWatermark()
    local badge = CreatorCredit.Badge{
        creator = credit.id,
        height = MAP_WATERMARK_HEIGHT,
        light = true,
        backing = true,
        label = T("hud.map_credit.lead"),
        hmargin = 16,
        vmargin = 16,
    }
    if badge == nil then
        return
    end
    host:AddChild(badge)
    --under the map's own HUD and dialogs (the Draw Steel banner).
    badge:SetAsFirstSibling()
    m_mapWatermark = badge
    m_mapWatermarkHost = host
    m_mapWatermarkCreator = credit.id
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
        return AboutLinkLabel{
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

    local function Fill(label, line)
        return function(credit)
            if credit ~= nil and label.valid then
                label:FireEvent("fill", line(AboutName(credit.name, credit.url, true)))
            end
        end
    end
    AboutEncounterAuthor(info.moduleid, Fill(authorLabel, function(name) return T("hud.about.written_by", { name = name }) end))
    AboutMapCreator(info.mapid, Fill(mapLabel, function(name) return T("hud.about.map_by", { name = name }) end))

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
                text = T("hud.about.encounter_heading", { title = info.title }),
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
    for _,credit in ipairs(ABOUT_CREDITS) do
        credits[#credits+1] = AboutLinkLabel{
            classes = {"eotwAboutCredit"},
            text = credit.line(AboutName(credit.name, credit.url)),
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
                badge = { hmargin = 16, vmargin = 12, light = true },
            },
        },

        gui.Label{
            classes = {"eotwAboutTitle"},
            text = T("hud.about.title"),
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
            text = T("hud.about.close"),
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
    --name is also the command's key (its keybinding); this is what the menu shows.
    gettext = function() return T("hud.about.menu_item") end,
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
