local mod = dmhub.GetModLoading()

--The Ctrl+Tab window switcher. Hold Ctrl and press Tab to step through the
--table's top-level windows -- map windows, scene windows and journal
--windows -- most recently used first; let go of Ctrl to bring the chosen one
--forward. Ctrl+Shift+Tab steps back, Escape cancels, a click picks a card.
--
--The engine sends the keys as the "switchwindow" / "switchwindowback" input
--events (InputController), even while a text field has the keyboard. It also
--stamps every raiseOnPress window's activationOrder on each press or raise,
--and that is the most-recently-used order. GameHud mounts the layer
--(WindowSwitcher.CreateLayer) over everything else in the hud.

--- One window the switcher can show (Tabletop.SwitcherMapWindows and
--- Tabletop.SwitcherSceneWindows make them for map and scene windows).
--- @class SwitcherWindow
--- @field key string unique among the windows
--- @field kind "map"|"scene"|"journal"
--- @field name string
--- @field panel Panel|nil the window's root panel; nil while it is unbuilt
--- @field image string|nil its picture
--- @field placeholder boolean|nil the picture is only a plain stand-in
--- @field icon string|nil the glyph shown when there is no picture
--- @field detail string|nil a short note under the name
--- @field minimized boolean
--- @field maximized boolean|nil
--- @field live boolean|nil a map window showing the live map
--- @field combat boolean|nil its map is in combat
--- @field onShow boolean|nil a scene shown to the players
--- @field activate fun() brings the window forward (opening a minimized one)

--- @class WindowSwitcherModule
WindowSwitcher = {}

--Card and layout sizes, in hud units (the hud is 1080 high).
local CARD_WIDTH = 232
local THUMB_HEIGHT = 130
local CARD_GAP = 12
local CARDS_PER_ROW = 6

--A quick Ctrl+Tab tap switches without the cards flashing up.
local SHOW_DELAY = 0.12

local KIND_ICONS = {
    map = "phosphor/map-trifold.png",
    scene = "phosphor/film-slate.png",
    journal = "phosphor/book-open-text.png",
}

local KIND_NAMES = {
    map = "Map",
    scene = "Scene",
    journal = "Journal",
}

--{layer, entries, index, openedAt, popup}: entries is nil while closed.
local g_state = {}

local g_styles = {
    {
        selectors = {"switcherBackdrop"},
        bgcolor = "#100d0be0",
        borderWidth = 1,
        borderColor = "#b8925a73",
        cornerRadius = 12,
        boxShadow = {x = 0, y = 18, blur = 60, spread = 6, color = "#000000d0"},
    },
    {
        selectors = {"switcherCard"},
        bgcolor = "#ffffff00",
        borderWidth = 2,
        borderColor = "#00000000",
        cornerRadius = 9,
    },
    {
        selectors = {"switcherCard", "hover"},
        bgcolor = "#ffffff0f",
    },
    {
        selectors = {"switcherCard", "selected"},
        bgcolor = "#ffffff17",
        borderColor = "#ffd27aff",
        transitionTime = 0.08,
    },
    {
        selectors = {"switcherThumb"},
        cornerRadius = 6,
        borderWidth = 1,
        borderColor = "#00000099",
    },
    {
        selectors = {"switcherThumb", "switcherPlain"},
        bgcolor = "#1d1915ff",
    },
    {
        selectors = {"switcherThumb", "switcherMinimized"},
        saturation = 0.35,
        brightness = 0.7,
    },
    {
        selectors = {"switcherBigIcon"},
        bgcolor = "#a99d8b80",
    },
    {
        selectors = {"switcherIcon"},
        bgcolor = "#d9d1c4",
    },
    {
        selectors = {"switcherIcon", "parent:selected"},
        bgcolor = "#ffd27a",
    },
    {
        selectors = {"switcherName"},
        color = "#ece4d6",
        fontSize = 15,
        bold = true,
    },
    {
        selectors = {"switcherDetail"},
        color = "#a99d8b",
        fontSize = 12,
    },
    {
        selectors = {"switcherBadge"},
        bgcolor = "#100d0bd9",
        cornerRadius = 4,
        color = "#ece4d6",
        fontSize = 11,
        bold = true,
    },
    {
        selectors = {"switcherBadge", "switcherCombat"},
        bgcolor = "#a3352ae6",
    },
    {
        selectors = {"switcherHint"},
        color = "#a99d8b",
        fontSize = 12,
    },
}

--The documents layer the in-app windows live in, or nil while the hud is down
--(GameHud.instance is false, not nil, then).
local function DocumentsLayer()
    local hud = GameHud.instance
    if not hud then
        return nil
    end
    local layer = hud.documentsPanel
    if layer == nil or not layer.valid then
        return nil
    end
    return layer
end

--The picture and glyph standing for a journal entry: a PDF's cover, an
--image, a bookmark's area; a document has only its glyph.
local function JournalLook(docid, fallbackDoc)
    local entry = CustomDocument.FindJournalEntry(docid) or fallbackDoc
    if entry == nil then
        return nil, KIND_ICONS.journal
    end
    local picture = nil
    pcall(function() picture = CustomDocument.JournalEntryPicture(entry) end)
    local icon = nil
    pcall(function() icon = CustomDocument.JournalEntryIcon(entry) end)
    return picture, icon or KIND_ICONS.journal
end

--The tabbed journal windows and the single-document windows
--(PresentDocument) in the documents layer. Popped-out windows live in their
--own OS windows and are left out, as are the icon rail's panel windows
--(their documents are not journal entries).
local function JournalWindows()
    local result = {}
    local layer = DocumentsLayer()
    if layer == nil then
        return result
    end
    local docs = dmhub.GetTable(CustomDocument.tableName) or {}

    for _, viewer in ipairs(CustomDocument.JournalViewers()) do
        local data = viewer.data
        if viewer.parent == layer and not data.poppedOut and #(data.tabs or {}) > 0 then
            local active = data.tabs[1]
            for _, tab in ipairs(data.tabs) do
                if tab.tabId == data.activeTabId then
                    active = tab
                end
            end
            local doc = docs[active.docId] or active.doc
            local picture, icon = JournalLook(active.docId, doc)
            local detail = "Journal"
            if #data.tabs > 1 then
                detail = string.format("Journal - %d tabs", #data.tabs)
            end
            result[#result+1] = {
                key = "journal:" .. viewer.id,
                kind = "journal",
                name = (doc ~= nil and doc.description) or "Untitled",
                panel = viewer,
                image = picture,
                icon = icon,
                detail = detail,
                minimized = data.minimized == true,
                maximized = data.maximized == true,
                activate = function()
                    if not viewer.valid then
                        return
                    end
                    if viewer.data.minimized then
                        viewer:FireEvent("restoreJournal")
                    else
                        --raises it and makes it the window documents open into.
                        viewer:FireEvent("click")
                    end
                end,
            }
        end
    end

    for _, child in ipairs(layer.children) do
        if child:HasClass("journalViewer") and not child:HasClass("journalTabbedViewer") then
            local docid = child.data.currentDocId
            local entry = CustomDocument.FindJournalEntry(docid)
            if entry ~= nil then
                local picture, icon = JournalLook(docid, entry)
                result[#result+1] = {
                    key = "journal:" .. child.id,
                    kind = "journal",
                    name = entry.description or "Untitled",
                    panel = child,
                    image = picture,
                    icon = icon,
                    detail = "Journal",
                    minimized = false,
                    activate = function()
                        if child.valid then
                            child:SetAsLastSibling()
                        end
                    end,
                }
            end
        end
    end

    return result
end

--- The journal windows, for the title bar's Windows menu too
--- (Tabletop.WindowsMenuEntries).
--- @return SwitcherWindow[]
WindowSwitcher.JournalWindows = JournalWindows

local function ActivationOrder(entry)
    local panel = entry.panel
    if panel == nil or not panel.valid then
        return 0
    end
    return panel.activationOrder or 0
end

--Every top-level window, most recently used first; minimized ones after the
--rest, as the OS switcher puts them.
local function CollectWindows()
    local list = {}
    local function add(entries)
        for _, entry in ipairs(entries) do
            list[#list+1] = entry
        end
    end
    add(Tabletop.SwitcherMapWindows())
    add(Tabletop.SwitcherSceneWindows())
    add(JournalWindows())
    table.sort(list, function(a, b)
        if a.minimized ~= b.minimized then
            return not a.minimized
        end
        local oa = ActivationOrder(a)
        local ob = ActivationOrder(b)
        if oa ~= ob then
            return oa > ob
        end
        return a.key < b.key
    end)
    return list
end

--The note under a card's name: what it is, and anything about its state.
local function DetailText(entry)
    local parts = {entry.detail or KIND_NAMES[entry.kind]}
    if entry.minimized then
        parts[#parts+1] = "minimized"
    elseif entry.maximized then
        parts[#parts+1] = "maximized"
    end
    return table.concat(parts, " - ")
end

--The small label over a card's picture, or nil.
local function BadgeText(entry)
    if entry.combat then
        return "In combat", true
    end
    if entry.live then
        return "Live", false
    end
    if entry.onShow then
        return "On show", false
    end
    return nil, false
end

local function BuildThumb(entry)
    local plain = entry.image == nil or entry.placeholder == true
    local children = {}
    if plain then
        children[#children+1] = gui.Panel{
            classes = {"switcherBigIcon"},
            interactable = false,
            width = 48,
            height = 48,
            halign = "center",
            valign = "center",
            bgimage = entry.icon or KIND_ICONS[entry.kind],
        }
    end
    local badge, combat = BadgeText(entry)
    if badge ~= nil then
        local badgeClasses = {"switcherBadge"}
        if combat then
            badgeClasses[#badgeClasses+1] = "switcherCombat"
        end
        children[#children+1] = gui.Label{
            classes = badgeClasses,
            interactable = false,
            bgimage = "panels/square.png",
            floating = true,
            text = badge,
            width = "auto",
            height = "auto",
            hpad = 6,
            vpad = 2,
            borderBox = true,
            halign = "left",
            valign = "top",
            hmargin = 6,
            vmargin = 6,
        }
    end
    local classes = {"switcherThumb"}
    if plain then
        classes[#classes+1] = "switcherPlain"
    end
    if entry.minimized then
        classes[#classes+1] = "switcherMinimized"
    end
    return gui.Panel{
        classes = classes,
        interactable = false,
        width = CARD_WIDTH - 16,
        height = THUMB_HEIGHT,
        halign = "center",
        bgimage = cond(plain, "panels/square.png", entry.image),
        bgcolor = cond(plain, "#1d1915ff", "white"),
        --cropped to fill, not stretched.
        nostretch = not plain,
        flow = "none",
        children = children,
    }
end

local Close
local Commit

local function BuildCard(entry, i)
    return gui.Panel{
        classes = {"switcherCard"},
        bgimage = "panels/square.png",
        width = CARD_WIDTH,
        height = "auto",
        flow = "vertical",
        pad = 8,
        borderBox = true,
        hmargin = CARD_GAP / 2,
        vmargin = CARD_GAP / 2,
        data = {index = i},
        click = function(element)
            g_state.index = i
            Commit()
        end,
        children = {
            BuildThumb(entry),
            gui.Panel{
                interactable = false,
                flow = "horizontal",
                width = "100%",
                height = 22,
                tmargin = 8,
                gui.Panel{
                    classes = {"switcherIcon"},
                    interactable = false,
                    width = 16,
                    height = 16,
                    valign = "center",
                    rmargin = 7,
                    bgimage = KIND_ICONS[entry.kind],
                },
                gui.Label{
                    classes = {"switcherName"},
                    interactable = false,
                    text = entry.name,
                    width = CARD_WIDTH - 16 - 23,
                    height = "auto",
                    valign = "center",
                    textWrap = false,
                    textOverflow = "ellipsis",
                },
            },
            gui.Label{
                classes = {"switcherDetail"},
                interactable = false,
                text = DetailText(entry),
                width = "100%",
                height = "auto",
                lmargin = 23,
                textWrap = false,
                textOverflow = "ellipsis",
            },
        },
    }
end

local function UpdateSelection()
    for i, card in ipairs(g_state.cards or {}) do
        if card.valid then
            card:SetClass("selected", i == g_state.index)
        end
    end
end

local function ShowPopup()
    local layer = g_state.layer
    local entries = g_state.entries
    if layer == nil or not layer.valid or entries == nil then
        return
    end
    local cards = {}
    for i, entry in ipairs(entries) do
        cards[#cards+1] = BuildCard(entry, i)
    end
    local perRow = math.min(#entries, CARDS_PER_ROW)
    local popup = gui.Panel{
        styles = g_styles,
        width = "100%",
        height = "100%",
        --a press anywhere off the cards cancels.
        bgimage = "panels/square.png",
        bgcolor = "#00000033",
        click = function(element)
            Close()
        end,
        captureEscape = true,
        escapePriority = EscapePriority.DMHUB_POPUP,
        escape = function(element)
            Close()
        end,
        gui.Panel{
            classes = {"switcherBackdrop"},
            bgimage = "panels/square.png",
            --frosted glass: the windows behind blur through the tint.
            frost = true,
            halign = "center",
            valign = "center",
            width = "auto",
            height = "auto",
            flow = "vertical",
            pad = 14,
            borderBox = true,
            --swallow presses between the cards, so they do not cancel.
            swallowPress = true,
            click = function(element) end,
            gui.Panel{
                width = perRow * (CARD_WIDTH + CARD_GAP),
                height = "auto",
                flow = "horizontal",
                wrap = true,
                halign = "center",
                children = cards,
            },
            gui.Label{
                classes = {"switcherHint"},
                interactable = false,
                text = "Tab: next     Shift+Tab: back     Esc: cancel",
                width = "auto",
                height = "auto",
                halign = "center",
                tmargin = 8,
            },
        },
    }
    g_state.popup = popup
    g_state.cards = cards
    layer:AddChild(popup)
    UpdateSelection()
end

Close = function()
    local popup = g_state.popup
    if popup ~= nil and popup.valid then
        popup:DestroySelf()
    end
    g_state.popup = nil
    g_state.cards = nil
    g_state.entries = nil
    local layer = g_state.layer
    if layer ~= nil and layer.valid then
        layer.thinkTime = nil
    end
end

Commit = function()
    local entries = g_state.entries
    local entry = entries ~= nil and entries[g_state.index] or nil
    Close()
    if entry ~= nil then
        entry.activate()
    end
end

local function Step(dir)
    local n = #g_state.entries
    g_state.index = ((g_state.index - 1 + dir) % n) + 1
    UpdateSelection()
end

local function Open(dir)
    if not Tabletop.IsActive() then
        return
    end
    --the live map window's picture shows the map as it is now.
    if Tabletop.LiveWindowState() ~= nil then
        dmhub.CaptureMapSnapshot()
    end
    local entries = CollectWindows()
    if #entries == 0 then
        return
    end
    g_state.entries = entries
    g_state.openedAt = dmhub.Time()
    --the first window is the one in use, so Tab starts on the one before it
    --(unless it is minimized: then nothing is in use).
    local first = cond(entries[1].minimized, 1, 2)
    if dir > 0 then
        g_state.index = math.min(first, #entries)
    else
        g_state.index = #entries
    end
    g_state.layer.thinkTime = 0.02
end

local function SwitchKey(dir)
    if g_state.entries == nil then
        Open(dir)
    else
        Step(dir)
    end
end

--- The switcher's layer. GameHud mounts it over everything else in the hud.
--- @return Panel
function WindowSwitcher.CreateLayer()
    g_state.entries = nil
    g_state.popup = nil
    g_state.cards = nil
    local layer
    layer = gui.Panel{
        id = "windowSwitcherLayer",
        width = "100%",
        height = "100%",
        interactable = false,
        inputEvents = {"switchwindow", "switchwindowback"},
        switchwindow = function(element)
            SwitchKey(1)
        end,
        switchwindowback = function(element)
            SwitchKey(-1)
        end,
        --polls while the switcher is open: letting go of Ctrl picks the card.
        think = function(element)
            if g_state.entries == nil or mod.unloaded then
                element.thinkTime = nil
                return
            end
            if not dmhub.modKeys.ctrl then
                Commit()
                return
            end
            if g_state.popup == nil and dmhub.Time() >= g_state.openedAt + SHOW_DELAY then
                ShowPopup()
            end
        end,
        destroy = function(element)
            if g_state.layer == element then
                g_state.layer = nil
                g_state.entries = nil
            end
        end,
    }
    g_state.layer = layer
    return layer
end
