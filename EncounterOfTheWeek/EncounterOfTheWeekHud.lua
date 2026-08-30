local mod = dmhub.GetModLoading()

--Encounter of the Week custom interface: usurps the normal game hud via
--the GameHud.RegisterCustomInterface core hook (DMHub Core UI/Hud.lua).
--While active it removes the icon-rail button columns (the docks slide
--away with them), removes the "Panels" title-bar menu, removes Compendium
--access (menus, toolbar, search), and mounts a hero roster on the right
--edge of the screen (shrinking itself to fit when a full seven-hero
--roster is taller than the window): one card per hero showing portrait,
--name, stamina,
--recoveries, heroic resource, surges, and condition icons. The local
--player's own heroes sit at the top, closer together, on a distinct
--backing. Clicking a card pops out the full character panel, which the
--characterPanelAccess override forces read-only for everyone.
--Design/plan doc: EncounterOfTheWeek/EncounterOfTheWeek.md.

--Hidden dev toggle: "/toggle eotw:forcecustomui" turns the custom
--interface on in ANY game (the authoring game included), for iterating on
--it without launching a real EotW game. The rails/title bar notice the
--flip within half a second.
setting{
    id = "eotw:forcecustomui",
    description = "Force the Encounter of the Week custom interface",
    default = false,
    storage = "preference",
}

--- Hero collection ----------------------------------------------------------

--All heroes in the party (on the current map or not), the local player's
--own first. "Own" is strict ownership (ownerId == loginUserid), not
--canControl: the EotW host can control everything but only their claimed
--heroes are theirs.
local function CollectHeroes()
    local result = {}
    local chars = nil
    pcall(function() chars = Party.GetPlayerCharacters() end)
    if chars == nil then
        return result
    end
    for charid, tok in pairs(chars) do
        if tok ~= nil and tok.valid then
            local isHero = false
            pcall(function() isHero = tok.properties ~= nil and tok.properties:IsHero() end)
            if isHero then
                local mine = false
                pcall(function() mine = tok.ownerId ~= nil and tok.ownerId == dmhub.loginUserid end)
                result[#result+1] = {
                    charid = charid,
                    mine = mine,
                    name = tok.name or "",
                }
            end
        end
    end
    table.sort(result, function(a, b)
        if a.mine ~= b.mine then
            return a.mine
        end
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.charid < b.charid
    end)
    return result
end

local function RosterSignature(heroes)
    local parts = {}
    for _, entry in ipairs(heroes) do
        parts[#parts+1] = string.format("%s:%s", entry.charid, tostring(entry.mine))
    end
    return table.concat(parts, "|")
end

--The condition + status-effect entries shown as icons on a card: the same
--table lookups the character panel's condition chips use.
local function CollectConditions(c)
    local entries = {}
    local conditionsTable = dmhub.GetTable("charConditions") or {}
    local inflicted = nil
    pcall(function() inflicted = c:try_get("inflictedConditions") end)
    for condid, _ in pairs(inflicted or {}) do
        local info = conditionsTable[condid]
        if info ~= nil then
            entries[#entries+1] = {
                icon = info.iconid,
                display = info.display or {},
                name = info.name or "Condition",
            }
        end
    end

    local ongoingTable = dmhub.GetTable("characterOngoingEffects") or {}
    local effects = nil
    pcall(function() effects = c:ActiveOngoingEffects() end)
    for _, entry in ipairs(effects or {}) do
        local info = ongoingTable[entry.ongoingEffectid]
        if info ~= nil and info.statusEffect then
            local icon = nil
            local display = nil
            pcall(function()
                icon = info:GetDisplayIcon()
                display = info:GetDisplayDisplay()
            end)
            if icon ~= nil then
                entries[#entries+1] = {
                    icon = icon,
                    display = display or {},
                    name = info.name or "Effect",
                }
            end
        end
    end
    return entries
end

--- Hero cards ---------------------------------------------------------------

local CARD_WIDTH = 132
local CARD_HEIGHT = 176
local OVERLAY_HEIGHT = 58
--condition chips in the card's top-right corner: the outer dark/red-bordered
--chip and the condition icon inside it.
local CONDITION_CHIP_SIZE = 26
local CONDITION_ICON_SIZE = 18

--The stamina bar: the character panel's health bar in miniature -- a
--theme-bordered track whose border and fill both track the
--healthy/winded/dying state (success/warning/danger, the documented
--stamina tiers), with a glossy vertical gradient on the fill, the
--cur/max numbers centered in white, and a temp-stamina segment in the
--accent color riding the end of the fill when the hero has any.
local function CreateStaminaBar(charid)
    local fill = gui.Panel{
        classes = {"fillBarFill", "healthFill"},
        width = "0%",
        height = "100%-2",
        valign = "center",
        halign = "left",
        lmargin = 1,
        bgimage = true,
        interactable = false,
    }
    local tempFill = gui.Panel{
        classes = {"fillBarFill", "eotwTempFill"},
        width = "0%",
        height = "100%-2",
        valign = "center",
        halign = "left",
        bgimage = true,
        interactable = false,
    }
    local numbers = gui.Label{
        classes = {"eotwBarLabel"},
        floating = true,
        halign = "center",
        valign = "center",
        text = "",
        interactable = false,
    }
    return gui.Panel{
        classes = {"bordered"},
        width = "100%",
        height = 14,
        flow = "horizontal",
        halign = "center",
        cornerRadius = 2,
        bgimage = true,
        bgcolor = "#00000066",
        interactable = false,
        fill,
        tempFill,
        numbers,
        refreshCard = function(element)
            local tok = dmhub.GetCharacterById(charid)
            if tok == nil or not tok.valid or tok.properties == nil then
                return
            end
            local c = tok.properties
            local cur, max, temp = 0, 0, 0
            local winded, dying = false, false
            pcall(function()
                cur = c:CurrentHitpoints()
                max = c:MaxHitpoints()
                temp = c:TemporaryHitpoints() or 0
                winded = cur <= c:BloodiedThreshold()
                dying = c:IsDying()
            end)
            local pct = 0
            if max > 0 then
                pct = math.max(0, math.min(1, cur / max))
            end
            local tempPct = 0
            if max > 0 and temp > 0 then
                tempPct = math.min(1 - pct, temp / max)
            end
            fill.selfStyle.width = string.format("%f%%", pct * 98)
            tempFill.selfStyle.width = string.format("%f%%", tempPct * 98)
            fill:SetClass("winded", winded)
            fill:SetClass("dying", dying)
            element:SetClass("borderSuccess", not winded and not dying)
            element:SetClass("borderWarning", winded and not dying)
            element:SetClass("borderDanger", dying)
            local text = string.format("%d/%d", cur, max)
            if temp > 0 then
                text = string.format("%s +%d", text, temp)
            end
            numbers.text = text
        end,
    }
end

--Heroic resource, icon only: the class's heroic resource icon (the
--character panel's own source) with the current value beside it. Surges
--are NOT here -- they render as per-surge icons in the card's bottom-right
--corner (CreateSurgeCorner).
local function CreateResourceRow(charid)
    local hrIcon = gui.Panel{
        classes = {"eotwResIcon"},
        interactable = false,
        refreshCard = function(element)
            local tok = dmhub.GetCharacterById(charid)
            if tok == nil or not tok.valid or tok.properties == nil then
                return
            end
            local icon = nil
            pcall(function()
                local classInfo = tok.properties:GetClass()
                if classInfo ~= nil then
                    icon = classInfo:try_get("heroicResourceIcon")
                end
            end)
            element:SetClass("hidden", icon == nil)
            if icon ~= nil then
                element.selfStyle.bgimage = icon
            end
        end,
        linger = function(element)
            local tok = dmhub.GetCharacterById(charid)
            if tok ~= nil and tok.valid and tok.properties ~= nil then
                local name = nil
                pcall(function() name = tok.properties:GetHeroicResourceName() end)
                gui.Tooltip(name or "Heroic Resource")(element)
            end
        end,
    }
    local hrValue = gui.Label{
        classes = {"eotwResValue"},
        text = "0",
        interactable = false,
        refreshCard = function(element)
            local tok = dmhub.GetCharacterById(charid)
            if tok == nil or not tok.valid or tok.properties == nil then
                return
            end
            local value = 0
            pcall(function() value = tok.properties:GetHeroicOrMaliceResources() or 0 end)
            element.text = tostring(value)
        end,
    }
    return gui.Panel{
        width = "100%",
        height = 16,
        flow = "horizontal",
        halign = "left",
        valign = "center",
        hrIcon,
        hrValue,
    }
end

--One surge icon PER available surge, in the card's bottom-right corner --
--and nothing at all when the hero has none. Rebuilt only when the count
--changes; display capped at 9 icons (they would outgrow the card).
local function CreateSurgeCorner(charid)
    return gui.Panel{
        floating = true,
        halign = "right",
        valign = "bottom",
        x = -4,
        y = -3,
        width = "auto",
        height = 13,
        flow = "horizontal",
        interactable = false,
        data = { count = nil },
        refreshCard = function(element)
            local tok = dmhub.GetCharacterById(charid)
            if tok == nil or not tok.valid or tok.properties == nil then
                return
            end
            local surges = 0
            pcall(function() surges = tok.properties:GetAvailableSurges() or 0 end)
            if surges == element.data.count then
                return
            end
            element.data.count = surges
            local icons = {}
            for i = 1, math.min(surges, 9) do
                icons[#icons+1] = gui.Panel{
                    classes = {"eotwSurgeIcon"},
                    interactable = false,
                }
            end
            element.children = icons
        end,
    }
end

local function CreateHeroCard(entry)
    local charid = entry.charid
    local mineClass = nil
    if entry.mine then
        mineClass = "mine"
    end

    local nameLabel = gui.Label{
        classes = {"eotwHeroName"},
        text = entry.name,
        interactable = false,
    }

    --condition icons over the artwork, packed into the TOP-RIGHT corner
    --(user direction 2026-08-29 -- they used to center across the top);
    --rebuilt only when the set actually changes. Each icon sits on a dark
    --red-bordered chip so it reads against any portrait.
    local conditionsRow = gui.Panel{
        floating = true,
        halign = "right",
        valign = "top",
        x = -4,
        y = 4,
        width = CARD_WIDTH - 8,
        height = "auto",
        flow = "horizontal",
        wrap = true,
        interactable = false,
        data = { signature = nil },
        refreshCard = function(element)
            local tok = dmhub.GetCharacterById(charid)
            if tok == nil or not tok.valid or tok.properties == nil then
                return
            end
            local entries = CollectConditions(tok.properties)
            local parts = {}
            for _, cond in ipairs(entries) do
                parts[#parts+1] = tostring(cond.icon)
            end
            local sig = table.concat(parts, "|")
            if sig == element.data.signature then
                return
            end
            element.data.signature = sig
            local icons = {}
            for _, cond in ipairs(entries) do
                local condName = cond.name
                --halign right on every chip is what right-packs the row:
                --the flow layout places the trailing run of halign="right"
                --children against the right edge, in order.
                icons[#icons+1] = gui.Panel{
                    halign = "right",
                    width = CONDITION_CHIP_SIZE,
                    height = CONDITION_CHIP_SIZE,
                    lmargin = 3,
                    bmargin = 3,
                    bgimage = "panels/square.png",
                    bgcolor = "#000000cc",
                    cornerRadius = 6,
                    border = 2,
                    borderColor = "#cc2222ff",
                    linger = function(iconElement)
                        gui.Tooltip(condName)(iconElement)
                    end,
                    gui.Panel{
                        width = CONDITION_ICON_SIZE,
                        height = CONDITION_ICON_SIZE,
                        halign = "center",
                        valign = "center",
                        bgimage = cond.icon,
                        bgcolor = cond.display.bgcolor or "white",
                        hueshift = cond.display.hueshift or 0,
                        saturation = cond.display.saturation or 1,
                        brightness = cond.display.brightness or 1,
                        interactable = false,
                    },
                }
            end
            element.children = icons
        end,
    }

    --the bottom-third overlay: name, stamina bar, resource icons on a
    --semi-opaque plate over the artwork.
    local overlay = gui.Panel{
        classes = {"eotwCardOverlay", mineClass},
        floating = true,
        halign = "center",
        valign = "bottom",
        width = "100%",
        height = OVERLAY_HEIGHT,
        flow = "vertical",
        bgimage = "panels/square.png",
        cornerRadius = 8,
        hpad = 6,
        vpad = 4,
        borderBox = true,
        interactable = false,

        nameLabel,
        CreateStaminaBar(charid),
        CreateResourceRow(charid),
    }

    --the card IS the portrait: full-bleed artwork with the overlay and
    --condition chips floating on top.
    return gui.Panel{
        classes = {"eotwHeroCard", mineClass},
        width = CARD_WIDTH,
        height = CARD_HEIGHT,
        halign = "right",
        cornerRadius = 8,
        bgimage = "panels/square.png",
        swallowPress = true,

        data = { charid = charid, mine = entry.mine },

        press = function(element)
            audio.FireSoundEvent("Mouse.Click")
            local toggle = rawget(_G, "ToggleCharacterPanelDocument")
            if toggle ~= nil then
                --anchored to this card: the window opens right beside it
                --instead of at the remembered/center position.
                toggle(charid, nil, element)
            end
        end,

        refreshCard = function(element)
            local tok = dmhub.GetCharacterById(charid)
            if tok == nil or not tok.valid then
                return
            end
            nameLabel.text = tok.name or ""
            local portrait = nil
            pcall(function() portrait = tok.offTokenPortrait end)
            if portrait ~= nil and portrait ~= "" then
                --bgcolor white keeps the artwork untinted; the card's
                --border and the overlay carry the mine/others styling.
                element.bgimage = portrait
                element.selfStyle.bgcolor = "white"
                local rect = nil
                pcall(function() rect = tok:GetPortraitRectForAspect(CARD_WIDTH / CARD_HEIGHT, portrait) end)
                element.selfStyle.imageRect = rect
            end
        end,

        conditionsRow,
        overlay,
        CreateSurgeCorner(charid),
    }
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

    local budget = (layerHeight - topInset - ROSTER_BOTTOM_GAP) / zoom
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
        local heroes = CollectHeroes()
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

        styles = ThemeEngine.MergeTokens{
            {
                selectors = {"eotwHeroCard"},
                bgcolor = "#151515",
                border = 1,
                borderColor = "#000000cc",
                transitionTime = 0.15,
            },
            {
                selectors = {"eotwHeroCard", "hover"},
                brightness = 1.15,
                borderColor = "#ffffff88",
            },
            {
                selectors = {"eotwHeroCard", "mine"},
                border = 2,
                borderColor = "#6fa8ffcc",
            },
            {
                selectors = {"eotwHeroCard", "mine", "hover"},
                borderColor = "#9cc4ffff",
            },
            {
                selectors = {"eotwCardOverlay"},
                bgcolor = "#000000c0",
            },
            {
                selectors = {"eotwCardOverlay", "mine"},
                bgcolor = "#0d1e31d0",
            },
            {
                selectors = {"eotwHeroName"},
                fontSize = 12,
                bold = true,
                color = "#ffffff",
                width = "100%",
                height = 15,
                textAlignment = "left",
                textWrap = false,
                bmargin = 3,
            },
            {
                selectors = {"eotwResIcon"},
                width = 14,
                height = 14,
                halign = "left",
                valign = "center",
                bgcolor = "white",
            },
            {
                selectors = {"eotwResValue"},
                fontSize = 12,
                bold = true,
                color = "#ffffff",
                width = "auto",
                height = "auto",
                --both the icon and the value align left so the flow packs
                --them together instead of spreading them across the row.
                halign = "left",
                valign = "center",
                lmargin = 3,
            },
            --the health bar's state tints, copied from the character
            --panel's HealthFill styles: success/warning/danger are the
            --documented theme tiers for stamina. The gradient overrides
            --the global fillBarFill's flat horizontal shade with a glossy
            --vertical one; grayscale stops so the bgcolor tint carries
            --the state color.
            {
                selectors = {"fillBarFill", "healthFill"},
                bgcolor = "@success",
                gradient = gui.Gradient{
                    point_a = {x = 0, y = 0},
                    point_b = {x = 0, y = 1},
                    stops = {
                        { position = 0, color = "#5A5A5A" },
                        { position = 0.45, color = "#8E8E8E" },
                        { position = 0.55, color = "#B4B4B4" },
                        { position = 1, color = "#E4E4E4" },
                    },
                },
            },
            {
                selectors = {"healthFill", "winded"},
                transitionTime = 0.4,
                bgcolor = "@warning",
            },
            {
                selectors = {"healthFill", "dying"},
                transitionTime = 0.4,
                bgcolor = "@danger",
            },
            {
                selectors = {"fillBarFill", "eotwTempFill"},
                bgcolor = "@accent",
                gradient = gui.Gradient{
                    point_a = {x = 0, y = 0},
                    point_b = {x = 0, y = 1},
                    stops = {
                        { position = 0, color = "#6A6A6A" },
                        { position = 1, color = "#E4E4E4" },
                    },
                },
            },
            {
                selectors = {"eotwBarLabel"},
                fontSize = 10,
                bold = true,
                color = "#ffffff",
                width = "100%",
                height = "100%",
                textAlignment = "center",
                textWrap = false,
            },
            {
                selectors = {"eotwSurgeIcon"},
                width = 12,
                height = 12,
                valign = "center",
                lmargin = 1,
                bgimage = "game-icons/surge.png",
                bgcolor = "white",
            },
        },

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

--The bottom-left corner strip: the Chat and Action Log buttons survive
--the takeover (user direction 2026-08-28) so players keep chat and the
--roll history.
local function CreateCornerButtonsPanel()
    local buttons = {}
    for _, name in ipairs({"Chat", "Action Log"}) do
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

--- The custom-interface registration ----------------------------------------

--pcall: an older core codex without the hook just shows the normal hud.
pcall(function()
    GameHud.RegisterCustomInterface{
        id = "eotw",

        active = function()
            if dmhub.GetSettingValue("eotw:forcecustomui") == true then
                return true
            end
            local eotw = rawget(_G, "EncounterOfTheWeekGame")
            if eotw == nil or not eotw.IsEotwGame() then
                return false
            end
            --the Director-UI escape hatch restores the whole normal
            --interface for debugging/manual recovery.
            return dmhub.GetSettingValue("eotw:showdirectorui") ~= true
        end,

        suppressRails = true,

        --the roster hangs off the RIGHT edge; the kept rail buttons stay
        --in the bottom-LEFT corner where the real rail's are.
        railPanel = function(side)
            if side == "right" then
                return CreateHeroRosterPanel()
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
    }
end)
