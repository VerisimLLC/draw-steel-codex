local mod = dmhub.GetModLoading()

--Encounter of the Week custom interface: usurps the normal game hud via
--the GameHud.RegisterCustomInterface core hook (DMHub Core UI/Hud.lua).
--While active it removes the icon-rail button columns (the docks slide
--away with them), removes the "Panels" title-bar menu, removes Compendium
--access (menus, toolbar, search), and mounts a hero roster on the left
--edge of the screen: one card per hero showing portrait, name, stamina,
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

local CARD_WIDTH = 204
local PORTRAIT_WIDTH = 54
local PORTRAIT_HEIGHT = 72

--The small portrait card: the character panel's portrait-frame recipe in
--miniature -- frame (portraitBackground) over a dark backing plate, with
--the portrait inset and cropped to the frame's aspect. bgcolor stays
--white on the body so the artwork keeps its natural colors.
local function CreatePortraitPanel(charid)
    return gui.Panel{
        classes = {"eotwHeroPortrait"},
        width = PORTRAIT_WIDTH,
        height = PORTRAIT_HEIGHT,
        halign = "left",
        valign = "center",
        bgimage = "panels/square.png",
        bgcolor = "#050505",
        cornerRadius = 6,

        gui.Panel{
            classes = {"eotwHeroPortraitBody"},
            width = "100%-2",
            height = "100%-2",
            halign = "center",
            valign = "center",
            cornerRadius = 6,
            bgcolor = "white",
            interactable = false,
            refreshCard = function(element)
                local tok = dmhub.GetCharacterById(charid)
                if tok == nil or not tok.valid then
                    return
                end
                local portrait = nil
                pcall(function() portrait = tok.offTokenPortrait end)
                if portrait == nil then
                    return
                end
                element.bgimage = portrait
                local rect = nil
                pcall(function() rect = tok:GetPortraitRectForAspect(PORTRAIT_WIDTH / PORTRAIT_HEIGHT, portrait) end)
                element.selfStyle.imageRect = rect
            end,
        },

        refreshCard = function(element)
            local tok = dmhub.GetCharacterById(charid)
            if tok == nil or not tok.valid then
                return
            end
            local frame = nil
            pcall(function() frame = tok.portraitBackground end)
            if frame ~= nil and frame ~= "" then
                element.bgimage = frame
                element.selfStyle.bgcolor = "white"
            end
        end,
    }
end

local function CreateHeroCard(entry)
    local charid = entry.charid

    local nameLabel = gui.Label{
        classes = {"eotwHeroName"},
        text = entry.name,
        interactable = false,
    }

    local statLine1 = gui.Label{
        classes = {"eotwHeroStat"},
        text = "",
        interactable = false,
    }

    local statLine2 = gui.Label{
        classes = {"eotwHeroStat"},
        text = "",
        interactable = false,
    }

    --condition icons; rebuilt only when the set actually changes.
    local conditionsRow = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        wrap = true,
        halign = "left",
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
                icons[#icons+1] = gui.Panel{
                    width = 14,
                    height = 14,
                    rmargin = 2,
                    bgimage = cond.icon,
                    bgcolor = cond.display.bgcolor or "white",
                    hueshift = cond.display.hueshift or 0,
                    saturation = cond.display.saturation or 1,
                    brightness = cond.display.brightness or 1,
                    linger = function(iconElement)
                        gui.Tooltip(condName)(iconElement)
                    end,
                }
            end
            element.children = icons
        end,
    }

    return gui.Panel{
        classes = {"eotwHeroCard", cond(entry.mine, "mine", nil)},
        width = CARD_WIDTH,
        height = "auto",
        flow = "horizontal",
        pad = 6,
        borderBox = true,
        halign = "left",
        bgimage = "panels/square.png",
        blurBackground = true,
        swallowPress = true,

        data = { charid = charid, mine = entry.mine },

        press = function(element)
            audio.FireSoundEvent("Mouse.Click")
            local toggle = rawget(_G, "ToggleCharacterPanelDocument")
            if toggle ~= nil then
                toggle(charid)
            end
        end,

        hover = function(element)
            local tok = dmhub.GetCharacterById(charid)
            if tok ~= nil and tok.valid then
                gui.Tooltip(string.format("%s: view character panel", tok.name or "Hero"))(element)
            end
        end,

        CreatePortraitPanel(charid),

        gui.Panel{
            width = string.format("%d", CARD_WIDTH - PORTRAIT_WIDTH - 20),
            height = "auto",
            flow = "vertical",
            lmargin = 6,
            halign = "left",
            valign = "center",
            interactable = false,

            nameLabel,
            statLine1,
            statLine2,
            conditionsRow,
        },

        refreshCard = function(element)
            local tok = dmhub.GetCharacterById(charid)
            if tok == nil or not tok.valid or tok.properties == nil then
                return
            end
            local c = tok.properties
            nameLabel.text = tok.name or ""

            local cur, max, temp = 0, 0, 0
            pcall(function()
                cur = c:CurrentHitpoints()
                max = c:MaxHitpoints()
                temp = c:TemporaryHitpoints() or 0
            end)
            local recoveries, maxRecoveries = 0, 0
            pcall(function()
                local recoveryid = CharacterResource.recoveryResourceId
                maxRecoveries = c:GetResources()[recoveryid] or 0
                recoveries = maxRecoveries - (c:GetResourceUsage(recoveryid, "long") or 0)
            end)
            local stamina = string.format("Stamina %d/%d", cur, max)
            if temp > 0 then
                stamina = string.format("%s +%d", stamina, temp)
            end
            statLine1.text = string.format("%s  Rec %d/%d", stamina, recoveries, maxRecoveries)

            local hrName = "Resource"
            local hrValue = 0
            local surges = 0
            pcall(function() hrName = c:GetHeroicResourceName() or "Resource" end)
            pcall(function() hrValue = c:GetHeroicOrMaliceResources() or 0 end)
            pcall(function() surges = c:GetAvailableSurges() or 0 end)
            statLine2.text = string.format("%s %d  Surges %d", hrName, hrValue, surges)
        end,
    }
end

--- The roster panel ---------------------------------------------------------

--Built fresh by the custom-interface rail host each time the rails build.
--Rebuilds its cards when party membership changes; individual card stats
--refresh on a 1s think plus the /characters monitor for prompt updates.
local function CreateHeroRosterPanel()
    local m_signature = nil

    local function Refresh(element)
        local heroes = CollectHeroes()
        local sig = RosterSignature(heroes)
        if sig ~= m_signature then
            m_signature = sig
            local cards = {}
            local seenOther = false
            for _, entry in ipairs(heroes) do
                local card = CreateHeroCard(entry)
                if entry.mine then
                    card.selfStyle.vmargin = 2
                else
                    --a wider gap separates the local player's group from
                    --everyone else's heroes.
                    if not seenOther then
                        card.selfStyle.tmargin = 16
                        card.selfStyle.bmargin = 3
                        seenOther = true
                    else
                        card.selfStyle.vmargin = 3
                    end
                end
                cards[#cards+1] = card
            end
            element.children = cards
        end
        element:FireEventTree("refreshCard")
    end

    return gui.Panel{
        id = "eotwHeroRoster",
        width = "auto",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",

        styles = {
            {
                selectors = {"eotwHeroCard"},
                bgcolor = "#000000cc",
                cornerRadius = 8,
                transitionTime = 0.15,
            },
            {
                selectors = {"eotwHeroCard", "hover"},
                bgcolor = "#000000ee",
            },
            {
                selectors = {"eotwHeroCard", "mine"},
                bgcolor = "#0d1e31d8",
                border = 1,
                borderColor = "#6fa8ff66",
            },
            {
                selectors = {"eotwHeroCard", "mine", "hover"},
                bgcolor = "#14293fee",
                borderColor = "#6fa8ffaa",
            },
            {
                selectors = {"eotwHeroName"},
                fontSize = 13,
                bold = true,
                color = "#ffffff",
                width = "100%",
                height = "auto",
                textAlignment = "left",
            },
            {
                selectors = {"eotwHeroStat"},
                fontSize = 11,
                color = "#ccccccff",
                width = "100%",
                height = "auto",
                textAlignment = "left",
            },
        },

        create = function(element)
            Refresh(element)
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

        railPanel = function(side)
            if side == "left" then
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
