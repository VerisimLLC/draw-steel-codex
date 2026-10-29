local mod = dmhub.GetModLoading()

--The [[link:Name]] tag in a journal document: a card for a map, a bestiary
--monster or a character, made by dragging one onto a document you can edit
--(see "Dropping items" in DocumentSystem.lua). It works like a chat link
--(ChatItemLinks.lua): clicking opens the item, and the name and picture are
--read live, so a rename shows and each reader sees only the names they may see.
--A map card shows the map's picture, and dragging it out opens the map in a
--window on the table; any card can also be dragged into chat or another
--document.
--
--RichItemLink.MarkupForDrop turns dropped items into document text: these
--cards, an existing scene tag for a scene, and an inline [Name](journal:id)
--link for a journal entry.

---@class RichItemLink: RichTag
--- @field new fun(o?: table): RichItemLink
--- @field kind "map"|"monster"|"character"
--- @field linkid string The map, bestiary monster or character id.
RichItemLink = RegisterGameType("RichItemLink", "RichTag")
RichItemLink.tag = "link"
--made only by drops, so a hand-typed [[link:X]] stays plain text, and there
--is nothing to edit in the annotations strip.
RichItemLink.hasEdit = false
RichItemLink.kind = "map"
RichItemLink.linkid = ""

function RichItemLink.Create()
    return RichItemLink.new{}
end

--- The chat-link form of this card (what ChatItemLinks opens and describes).
--- @return ChatItemLink
function RichItemLink:Item()
    return {kind = self.kind, id = self.linkid}
end

local MAP_WIDTH = 288
local MAP_PICTURE_HEIGHT = 162
local ROW_WIDTH = 260
local PORTRAIT_SIZE = 44

local function CardStyles(pal)
    local styles = {
        {
            selectors = {"itemLinkCard"},
            bgcolor = "@bgAlt",
            borderColor = "@border",
            borderWidth = 1,
            cornerRadius = 4,
        },
        {
            selectors = {"itemLinkCard", "hover"},
            borderColor = "@accent",
            transitionTime = 0.1,
        },
        {
            selectors = {"itemLinkCard", "press"},
            brightness = 0.85,
        },
        {
            selectors = {"itemLinkName"},
            color = "@fgStrong",
        },
        {
            selectors = {"itemLinkKind"},
            color = "@fgMuted",
        },
        {
            selectors = {"itemLinkIcon"},
            bgcolor = "@fgMuted",
        },
    }
    --on a skinned page the card takes the page's colours (RichScene does the same).
    if pal ~= nil then
        styles[#styles + 1] = { selectors = {"itemLinkCard"}, bgcolor = pal.page, borderColor = pal.border }
        styles[#styles + 1] = { selectors = {"itemLinkCard", "hover"}, borderColor = pal.accent }
        styles[#styles + 1] = { selectors = {"itemLinkName"}, color = pal.ink }
        styles[#styles + 1] = { selectors = {"itemLinkKind"}, color = pal.ink }
        styles[#styles + 1] = { selectors = {"itemLinkIcon"}, bgcolor = pal.ink }
    end
    return ThemeEngine.MergeTokens(styles)
end

--The name and kind lines.
local function NameLines(info, width)
    return gui.Panel{
        width = width,
        height = "auto",
        valign = "center",
        flow = "vertical",
        gui.Label{
            classes = {"sizeS", "itemLinkName"},
            width = "100%",
            height = "auto",
            bold = true,
            textWrap = false,
            text = info.name,
        },
        gui.Label{
            classes = {"sizeXxs", "itemLinkKind"},
            width = "100%",
            height = "auto",
            textWrap = false,
            text = info.kind,
        },
    }
end

--A map card: the map's picture over its name.
local function MapCardContent(item, info)
    return {
        gui.Panel{
            width = "100%",
            height = MAP_PICTURE_HEIGHT,
            bgimage = "panels/square.png",
            bgcolor = "black",
            --behind the picture: shows while it loads, or when the map has none.
            gui.Panel{
                classes = {"itemLinkIcon"},
                width = 40,
                height = 40,
                halign = "center",
                valign = "center",
                bgimage = info.icon,
            },
            MapThumbnail.Panel{
                mapid = item.id,
                width = MAP_WIDTH - 10,
                height = MAP_PICTURE_HEIGHT,
                halign = "center",
                valign = "center",
                floating = true,
            },
        },
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            tmargin = 4,
            gui.Panel{
                classes = {"itemLinkIcon"},
                width = 18,
                height = 18,
                valign = "center",
                rmargin = 6,
                bgimage = info.icon,
            },
            NameLines(info, MAP_WIDTH - 40),
        },
    }
end

--A monster or character card: portrait beside the name.
local function RowCardContent(item, info)
    local picture
    if info.image ~= nil then
        picture = gui.Panel{
            width = "auto",
            height = "auto",
            maxWidth = PORTRAIT_SIZE,
            maxHeight = PORTRAIT_SIZE,
            autosizeimage = true,
            halign = "center",
            valign = "center",
            bgimage = info.image,
            bgcolor = "white",
        }
    else
        picture = gui.Panel{
            classes = {"itemLinkIcon"},
            width = 24,
            height = 24,
            halign = "center",
            valign = "center",
            bgimage = info.icon,
        }
    end
    return {
        gui.Panel{
            width = PORTRAIT_SIZE,
            height = PORTRAIT_SIZE,
            valign = "center",
            rmargin = 8,
            picture,
        },
        NameLines(info, ROW_WIDTH - PORTRAIT_SIZE - 24),
    }
end

function RichItemLink.CreateDisplay(self)
    local m_tag = self
    --the tag's text in the document ("link:Goblin"), from the last render.
    local m_tagText = nil
    --what the card was last built from, so a render with nothing new keeps it.
    local m_built = nil

    --Dragged within its own document the card moves there. Which copy of its
    --tag this card is comes from its annotation's key: the first copy is
    --keyed by the tag's text, later ones text-1, text-2, ... (the order
    --MarkdownDocument's renderers use).
    local function MoveItem()
        local doc = m_tag:GetDocument()
        if doc == nil or m_tagText == nil then
            return nil
        end
        local text = m_tagText
        for key, annotation in pairs(doc:try_get("annotations") or {}) do
            if rawequal(annotation, m_tag) then
                local occurrence = nil
                if key == text then
                    occurrence = 1
                elseif key:sub(1, #text + 1) == text .. "-" then
                    local n = tonumber(key:sub(#text + 2))
                    if n ~= nil then
                        occurrence = n + 1
                    end
                end
                if occurrence ~= nil then
                    ---@type ItemLinkMove
                    local move = {kind = "move", tag = text, occurrence = occurrence, docid = doc.id, item = m_tag:Item()}
                    return move
                end
            end
        end
        return nil
    end

    local card
    card = gui.Panel{
        classes = {"itemLinkCard"},
        bgimage = true,
        height = "auto",
        valign = "center",
        pad = 5,
        borderBox = true,

        refreshTag = function(element, tag, match, token)
            if tag ~= nil then
                m_tag = tag --[[@as RichItemLink]]
            end
            if token ~= nil and type(token.text) == "string" then
                m_tagText = token.text
            end
            element.selfStyle.halign = (token ~= nil and token.justification) or "left"
            element.styles = CardStyles(MarkdownDocument.PageSkinPalette(m_tag:GetDocument()))

            local item = m_tag:Item()
            local info = ChatItemLinks.Describe(item)
            local key = string.format("%s:%s:%s:%s", item.kind, item.id, info.name, tostring(info.image))
            if key == m_built then
                return
            end
            m_built = key

            local children
            if item.kind == "map" then
                element.selfStyle.width = MAP_WIDTH
                element.selfStyle.flow = "vertical"
                children = MapCardContent(item, info)
            else
                element.selfStyle.width = ROW_WIDTH
                element.selfStyle.flow = "horizontal"
                children = RowCardContent(item, info)
            end
            element.children = children
            --the card takes every click and drag, not its pieces.
            for _, child in ipairs(children) do
                child:MakeNonInteractiveRecursive()
            end
        end,

        hover = function(element)
            local info = ChatItemLinks.Describe(m_tag:Item())
            if m_tag.kind == "map" then
                gui.Tooltip(string.format("Click to open %s. Drag it onto the table to open it in a window there.", info.name))(element)
            else
                gui.Tooltip(string.format("Click to open %s", info.name))(element)
            end
        end,

        click = function(element)
            ChatItemLinks.Open(m_tag:Item())
        end,

        --dragging: within its own document it moves there; out, into chat or
        --another document, a map onto the table, where it opens in a window
        --under the mouse, and (for the Director) a monster onto a map or the
        --table, as a bestiary row drag does.
        draggable = true,
        canDragOnto = function(element, target)
            return false
        end,
        beginDrag = function(element)
            local item = m_tag:Item()
            if item.kind == "monster" and dmhub.isDM and assets.monsters[item.id] ~= nil then
                --the engine places whatever the focused panel names
                --(CharacterPanel's dmhub.GetSelectedMonster).
                element.data.monsterid = item.id
                gui.SetFocus(element)
            end
        end,
        dragging = function(element, target)
            local item = m_tag:Item()
            ChatItemLinks.Dragging(function() return {item} end, {
                source = element,
                homeItems = function() return {MoveItem()} end,
            })
            if item.kind == "map" then
                Tabletop.MapRowDragging(element, item.id)
            elseif item.kind == "monster" and element.data.monsterid == item.id then
                dmhub.SetDraggingMonster()
                local selected = dmhub.GetSelectedMonster()
                if selected ~= nil then
                    Tabletop.BestiaryRowDragging(element, selected.monsterid, selected.quantity)
                end
            end
        end,
        drag = function(element, target)
            local item = m_tag:Item()
            if item.kind == "map" then
                Tabletop.MapRowDragEnded(element)
            elseif element.data.monsterid ~= nil then
                Tabletop.BestiaryRowDragEnded(element)
                --the engine places the monster on release, after this; then
                --drop the focus, or its placement ghost would keep following
                --the mouse.
                dmhub.Schedule(0.2, function()
                    if not element.valid then
                        return
                    end
                    element.data.monsterid = nil
                    if gui.GetFocus() == element then
                        gui.SetFocus(nil)
                    end
                end)
            end
            if ChatItemLinks.Dropped() then
                return
            end
            if item.kind == "map" and dmhub.panelDropSurface == "table" then
                local map = game.GetMap(item.id)
                if map == nil or not map.valid then
                    return
                end
                --as clicking does, a player who can't open the map gets a view of it.
                if not Tabletop.CanAccessMap(item.id) then
                    dmhub.GrantLinkedMapView(item.id)
                end
                Tabletop.MapRowDropped(item.id)
            end
        end,
    }
    return card
end

----------------------------------------------------------------------
--Turning dropped items into document text.

--Characters that would break [label](target) link syntax.
local function LinkLabel(name)
    local label = string.trim((string.gsub(name or "", "[%[%]\r\n]", "")))
    if label == "" then
        return "Link"
    end
    return label
end

--- What dropped items become in doc, one entry each: an inline link
--- ("[Name](journal:id)") for a journal entry, or a "[[tag]]" whose data is
--- added to doc.annotations here -- a card for a map, monster or character, a
--- scene tag for a scene, or the dragged tag itself (an encounter). The
--- caller writes the text; a tag needs a line to itself.
--- @param doc MarkdownDocument
--- @param items ItemLinkDrop[]
--- @return {text: string, inline: boolean}[]
function RichItemLink.MarkupForDrop(doc, items)
    local result = {}
    for _, item in ipairs(items or {}) do
        local kind = item.kind
        if kind == "doc" then
            ---@cast item ChatItemLink
            local info = ChatItemLinks.Describe(item)
            result[#result + 1] = {
                text = string.format("[%s](journal:%s)", LinkLabel(info.name), item.id),
                inline = true,
            }
        else
            local richTag, name = nil, nil
            if kind == "richtag" then
                richTag, name = item.richTag, item.name
            elseif kind == "scene" then
                ---@cast item ChatItemLink
                if Scenes.Get(item.id) ~= nil then
                    richTag = RichScene.new{ scene = item.id }
                    name = Scenes.Name(item.id)
                end
            elseif kind == "map" or kind == "monster" or kind == "character" then
                ---@cast item ChatItemLink
                richTag = RichItemLink.new{ kind = kind, linkid = item.id }
                name = ChatItemLinks.Describe(item).name
            end
            if richTag ~= nil then
                local key = doc:AddRichTagAnnotation(richTag, name)
                result[#result + 1] = { text = "[[" .. key .. "]]", inline = false }
            end
        end
    end
    return result
end

--- Moves a card's line (move, from a card dragged within its document) so it
--- goes in front of line at (#lines + 1: the end). lines is the document's
--- text split on newlines and is changed in place. Copies of one tag are told
--- apart by their order (the first keyed by the tag's text, then text-1,
--- text-2, ...), so when the tag appears more than once its annotations are
--- re-keyed to follow the move. Returns the moved line's new index, or nil
--- when nothing moved.
--- @param doc MarkdownDocument
--- @param lines string[]
--- @param move ItemLinkMove
--- @param at integer
--- @return nil|integer
function RichItemLink.MoveTagLine(doc, lines, move, at)
    --the tag alone on its line, after any justification markers (:<> etc.).
    local markup = "[[" .. move.tag .. "]]"
    local copies = {}
    for i, line in ipairs(lines) do
        if (line:gsub("^[:<>]+", "")) == markup then
            copies[#copies + 1] = i
        end
    end

    local from = copies[move.occurrence]
    if from == nil then
        return nil
    end
    at = math.max(1, math.min(at, #lines + 1))
    if at == from or at == from + 1 then
        return nil
    end
    local moved = table.remove(lines, from)
    if at > from then
        at = at - 1
    end
    table.insert(lines, at, moved)

    if #copies > 1 then
        local function KeyFor(n)
            if n == 1 then
                return move.tag
            end
            return string.format("%s-%d", move.tag, n - 1)
        end
        local annotations = doc:try_get("annotations") or {}
        local before = {}
        --where each copy's line is now.
        local newIndex = {}
        for n, i in ipairs(copies) do
            before[n] = annotations[KeyFor(n)]
            local j = i
            if n == move.occurrence then
                j = at
            else
                if i > from then
                    j = j - 1
                end
                if j >= at then
                    j = j + 1
                end
            end
            newIndex[n] = j
        end
        local order = {}
        for n = 1, #copies do
            order[n] = n
        end
        table.sort(order, function(a, b) return newIndex[a] < newIndex[b] end)
        for rank, n in ipairs(order) do
            annotations[KeyFor(rank)] = before[n]
        end
    end
    return at
end

--True when every item becomes an inline link (MarkupForDrop's inline), so
--a drop of them can go mid-line rather than on lines of their own. Unlike
--MarkupForDrop it changes nothing, so a drag hover can ask it.
---@param items ChatItemLink[]|nil
---@return boolean
function RichItemLink.DropIsInline(items)
    for _, item in ipairs(items or {}) do
        if item.kind ~= "doc" then
            return false
        end
    end
    return true
end

----------------------------------------------------------------------
--The card following the mouse while items are dragged over a document.

--Screen pixels from the top-left to a hud layer's own units (the layers sit
--below the title bar and may be scaled).
local function ScreenToLayer(layer, px, py)
    local screen = dmhub.screenDimensions
    local below = dmhub.screenDimensionsBelowTitlebar
    if below.y <= 0 then
        return px, py
    end
    local scale = layer.renderedHeight / below.y
    return px * scale, (py - (screen.y - below.y)) * scale
end

local MAX_GHOST_PICTURES = 4

--- Shows a small card by the mouse saying what dropping items here adds.
--- think() is called every frame while it shows; the card destroys itself
--- when think returns false (the caller may also destroy it).
--- text replaces the card's own wording (files dragged in from the desktop
--- pass no items, only text).
--- @param items ItemLinkDrop[]
--- @param think fun(ghost: Panel): boolean
--- @param text nil|string
--- @return nil|Panel
function RichItemLink.ShowDropGhost(items, think, text)
    local hud = GameHud.instance --[[@as GameHud]]
    if hud == nil then
        return nil
    end
    --the banner layer sits above every window.
    local layer = hud.bannerLayer
    if layer == nil or not layer.valid then
        layer = hud.documentsPanel
    end
    if layer == nil or not layer.valid then
        return nil
    end

    local pictures = {}
    local names = {}
    for _, item in ipairs(items) do
        if item.kind == "move" then
            item = item.item
        end
        if item.kind == "richtag" then
            names[#names + 1] = item.name
        else
            ---@cast item ChatItemLink
            local info = ChatItemLinks.Describe(item)
            names[#names + 1] = info.name
            if #pictures < MAX_GHOST_PICTURES then
                pictures[#pictures + 1] = gui.Panel{
                    width = cond(info.wide, 64, 40),
                    height = 40,
                    valign = "center",
                    rmargin = 4,
                    gui.Panel{
                        width = "auto",
                        height = "auto",
                        maxWidth = cond(info.wide, 64, 40),
                        maxHeight = 40,
                        autosizeimage = true,
                        halign = "center",
                        valign = "center",
                        bgimage = info.image or info.icon,
                        bgcolor = cond(info.image ~= nil, "white", "@fg"),
                    },
                }
            end
        end
    end

    if text == nil then
        if #items == 1 and items[1].kind == "move" then
            text = string.format("Move %s here", names[1])
        elseif #items == 1 and items[1].kind == "doc" then
            text = string.format("Add a link to %s", names[1])
        elseif #names == 1 then
            text = string.format("Add %s", names[1])
        else
            text = string.format("Add %d items", #names)
        end
    end

    local ghost
    ghost = gui.Panel{
        classes = {"itemLinkDropGhost", "bordered", "bg"},
        styles = ThemeEngine.MergeTokens{
            {
                selectors = {"itemLinkDropGhost"},
                borderColor = "@accent",
                borderWidth = 2,
                cornerRadius = 6,
            },
        },
        halign = "left",
        valign = "top",
        width = "auto",
        height = "auto",
        flow = "horizontal",
        hpad = 8,
        vpad = 6,
        borderBox = true,
        bgimage = true,

        thinkTime = 0.01,
        think = function(element)
            if mod.unloaded or not think(element) then
                if element.valid then
                    element:DestroySelf()
                end
                return
            end
            --below and right of the pointer, clear of the drop target hit test.
            local mouse = dmhub.mouseScreenPosition
            element.x, element.y = ScreenToLayer(layer, mouse.x + 18, mouse.y + 22)
        end,

        gui.Panel{
            width = "auto",
            height = "auto",
            flow = "horizontal",
            valign = "center",
            children = pictures,
        },
        gui.Label{
            classes = {"sizeS"},
            width = "auto",
            maxWidth = 320,
            height = "auto",
            valign = "center",
            lmargin = 4,
            text = text,
        },
    }
    layer:AddChild(ghost)
    ghost:MakeNonInteractiveRecursive()
    ghost:SetAsLastSibling()
    local mouse = dmhub.mouseScreenPosition
    ghost.x, ghost.y = ScreenToLayer(layer, mouse.x + 18, mouse.y + 22)
    return ghost
end

MarkdownDocument.RegisterRichTag(RichItemLink)
