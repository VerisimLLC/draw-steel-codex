local mod = dmhub.GetModLoading()

--Item links in chat. Anything that can be dragged onto the table can also be
--dropped into chat: a map, a scene, a journal entry (document, PDF, image or
--PDF bookmark), a character or a bestiary monster. Everyone gets the message,
--and clicking a link opens the item, even for a player who could not open it
--otherwise (ChatItemLinks.Open).
--
--How a drop reaches chat:
--  * Panel drags (rows, table cards and items): the source calls
--    ChatItemLinks.Dragging from its "dragging" event and ChatItemLinks.Dropped
--    from its "drag" event. The chat panel is a token drop target, and
--    dmhub.tokenDropTargetUnderMouse looks past the dragged panel, so it names
--    the chat while the mouse is over it.
--  * Map tokens: the chat panel's dropTokens event (ChatPanel.lua) calls
--    ChatItemLinks.SendCharacters.
--
--The same drags reach other panels that take items, such as a journal
--document (DocumentSystem.lua). Such a panel sets tokenDropTarget = true and
--carries ChatItemLinks.ITEM_DROP_TARGET_CLASS, and gets these events:
--  "itemLinkDragHover"(items)  a drag came over it; (nil) it left
--  "itemLinkDrop"(items)       the drag was released over it
--While hovered it can follow the mouse itself (dmhub.mouseScreenPosition).

ChatItemLinks = {}

--A drop never posts more links than this in one message.
local MAX_ITEMS = 12

--The class the chat panel carries so drags can tell it from other drop targets.
ChatItemLinks.DROP_TARGET_CLASS = "chatItemDropTarget"

--The chat's icon rail button (DocumentSystem.lua): a drag that rests on it
--this long opens the chat ("springOpen"), and a drop on it posts the link.
ChatItemLinks.OPEN_TARGET_CLASS = "chatItemOpenTarget"
ChatItemLinks.SPRING_OPEN_DELAY = 0.4

--Any other panel that takes item drops (see the top of this file).
ChatItemLinks.ITEM_DROP_TARGET_CLASS = "itemLinkDropTarget"

--- @alias ChatItemLink {kind: "map"|"scene"|"doc"|"character"|"monster", id: string, name: nil|string}
--- @alias ChatItemLinkList (nil|ChatItemLink)[]
--- What a drag offers a panel other than the chat: a link, a ready-made rich
--- tag for a document (a dragged encounter), or a journal card being moved
--- within its own document (RichItemLink.lua: tag is the tag's text, occurrence
--- which copy of it, item the card's link for anywhere else).
--- A sound (an audio clip's asset id) dragged into a scene (SceneElements.lua);
--- only scenes take it, never chat (see targetClass).
--- @alias SceneAudioLink {kind: "audio", id: string}
--- @alias ItemLinkDrop ChatItemLink|{kind: "richtag", richTag: RichTag, name: string}|ItemLinkMove|SceneAudioLink
--- @alias ItemLinkMove {kind: "move", tag: string, occurrence: integer, docid: string, item: ChatItemLink}

----------------------------------------------------------------------
--Making links.

--- @param mapid nil|string
--- @return nil|ChatItemLink
function ChatItemLinks.MapItem(mapid)
    if type(mapid) ~= "string" or mapid == "" then
        return nil
    end
    local map = game.GetMap(mapid)
    if map == nil or not map.valid then
        return nil
    end
    return {kind = "map", id = mapid, name = map.description}
end

--- @param sceneid nil|string
--- @return nil|ChatItemLink
function ChatItemLinks.SceneItem(sceneid)
    if type(sceneid) ~= "string" or Scenes.Get(sceneid) == nil then
        return nil
    end
    return {kind = "scene", id = sceneid, name = Scenes.Name(sceneid)}
end

--- A journal entry: a document, PDF, image or PDF bookmark.
--- @param entryid nil|string
--- @return nil|ChatItemLink
function ChatItemLinks.DocItem(entryid)
    if type(entryid) ~= "string" then
        return nil
    end
    local entry = CustomDocument.FindJournalEntry(entryid)
    if entry == nil then
        return nil
    end
    local name = nil
    pcall(function() name = entry.description end)
    if type(name) ~= "string" or name == "" then
        pcall(function() name = entry.name end)
    end
    return {kind = "doc", id = entryid, name = name}
end

--- A character in the game (a hero, a monster on a map, a card on the table).
--- No name is stored: each client shows the name it is allowed to see.
--- @param charid nil|string
--- @return nil|ChatItemLink
function ChatItemLinks.CharacterItem(charid)
    if type(charid) ~= "string" or dmhub.GetCharacterById(charid) == nil then
        return nil
    end
    return {kind = "character", id = charid}
end

--- A bestiary entry, not yet in the game.
--- @param monsterid nil|string
--- @return nil|ChatItemLink
function ChatItemLinks.MonsterItem(monsterid)
    if type(monsterid) ~= "string" then
        return nil
    end
    local monster = assets.monsters[monsterid]
    if monster == nil then
        return nil
    end
    return {kind = "monster", id = monsterid, name = monster.name}
end

--- Posts links to chat, one message for the lot. nil entries are skipped.
--- @param items (nil|ChatItemLink)[]
--- @return boolean posted
function ChatItemLinks.Send(items)
    local list = {}
    local seen = {}
    for _, item in pairs(items or {}) do
        if type(item) == "table" and item.kind ~= nil and item.id ~= nil then
            local key = item.kind .. ":" .. item.id
            if not seen[key] and #list < MAX_ITEMS then
                seen[key] = true
                list[#list+1] = item
            end
        end
    end
    if #list == 0 then
        return false
    end
    chat.SendCustom(ChatItemLinkMessage.new{
        channel = "chat",
        items = list,
    })
    return true
end

--- Posts a link for each character (a map token drag dropped on chat).
--- @param charids string[]
function ChatItemLinks.SendCharacters(charids)
    local items = {}
    for _, charid in ipairs(charids or {}) do
        items[#items+1] = ChatItemLinks.CharacterItem(charid)
    end
    ChatItemLinks.Send(items)
end

----------------------------------------------------------------------
--Dragging onto chat (or another panel that takes items).

--The drop target the current drag is over: {target, items, seen, since,
--role, opened}, or nil. role is "chat", "button" (the chat's rail button) or
--"target" (any other panel that takes items).
local g_hover = nil

local function LinkText(items)
    if #items == 1 then
        local item = items[1]
        local name = item.name
        if item.kind == "character" then
            local token = dmhub.GetCharacterById(item.id)
            name = token ~= nil and creature.GetTokenDescription(token) or nil
        end
        if type(name) == "string" and name ~= "" then
            return string.format("Release to share %s in chat", name)
        end
        return "Release to share this in chat"
    end
    return string.format("Release to share %d items in chat", #items)
end

local function ClearHover()
    local hover = g_hover
    g_hover = nil
    if hover == nil or not hover.target.valid then
        return
    end
    if hover.role == "chat" then
        hover.target:FireEvent("chatItemDragHover", nil)
    elseif hover.role == "target" then
        hover.target:FireEvent("itemLinkDragHover", nil)
    end
end

--Whether panel is inside container (or is it). A card dragged out of a
--document gets options.homeItems there, or nothing (see Dragging).
--- @param container Panel
--- @param panel nil|Panel
--- @return boolean
local function IsInside(container, panel)
    while panel ~= nil do
        if panel == container then
            return true
        end
        panel = panel.parent
    end
    return false
end

--A drag can end without its source hearing of it (the row rebuilt
--mid-drag): the chat's highlight goes once Dragging stops being called.
local function WatchHover()
    dmhub.Schedule(0.2, function()
        if mod.unloaded or g_hover == nil then
            return
        end
        if dmhub.Time() - g_hover.seen > 0.3 then
            ClearHover()
            return
        end
        WatchHover()
    end)
end

--- @class ChatItemLinkDragOptions
--- @field source nil|Panel The dragged panel. A panel it came out of is not a target, unless homeItems is given.
--- @field dropItems nil|fun(): ItemLinkDrop[] What panels other than the chat get instead of the links.
--- @field homeItems nil|fun(): ItemLinkDrop[] What the panel source came out of gets (a card moved within its document).
--- @field targetClass nil|string Only drop targets carrying this class take the drop; the chat never does.

--- @param items function returns the links (or ItemLinkDrops); nil entries are skipped.
--- @return ItemLinkDrop[]
local function ListItems(items)
    local list = {}
    for _, item in pairs(items() or {}) do
        if type(item) == "table" then
            list[#list+1] = item
        end
    end
    return list
end

--- Call from a dragged panel's "dragging" event. Highlights the chat (or
--- another panel that takes items) while the mouse is over it; resting on the
--- chat's rail button opens the chat. items: a function returning the links a
--- drop there makes (called once per target entered).
--- @param items fun(): ChatItemLinkList
--- @param options? ChatItemLinkDragOptions
--- @return boolean overTarget
function ChatItemLinks.Dragging(items, options)
    options = options or {}
    local target = dmhub.tokenDropTargetUnderMouse
    local role = nil
    local home = false
    if target ~= nil then
        if target:HasClass(ChatItemLinks.OPEN_TARGET_CLASS) then
            role = "button"
        elseif target:HasClass(ChatItemLinks.DROP_TARGET_CLASS) then
            role = "chat"
        elseif target:HasClass(ChatItemLinks.ITEM_DROP_TARGET_CLASS) then
            home = IsInside(target, options.source)
            if not home or options.homeItems ~= nil then
                role = "target"
            end
        end
        if options.targetClass ~= nil and not target:HasClass(options.targetClass) then
            role = nil
        end
    end
    if target == nil or role == nil then
        ClearHover()
        return false
    end

    local now = dmhub.Time()
    if g_hover ~= nil and g_hover.target == target then
        g_hover.seen = now
        --resting on the chat's rail button opens the chat beside it.
        if role == "button" and not g_hover.opened and now - g_hover.since >= ChatItemLinks.SPRING_OPEN_DELAY then
            g_hover.opened = true
            target:FireEvent("springOpen")
        end
        return true
    end

    ClearHover()
    local list
    if role == "target" and home and options.homeItems ~= nil then
        list = ListItems(options.homeItems)
    elseif role == "target" and options.dropItems ~= nil then
        list = ListItems(options.dropItems)
    else
        list = ListItems(items)
    end
    if #list == 0 then
        return false
    end
    g_hover = {target = target, items = list, seen = now, since = now, role = role, opened = false}
    if role == "chat" then
        target:FireEvent("chatItemDragHover", LinkText(list))
    elseif role == "target" then
        target:FireEvent("itemLinkDragHover", list)
    end
    WatchHover()
    return true
end

--- Call from a dragged panel's "drag" event, before anything else: posts the
--- links when it was released over the chat, or hands them to the panel it
--- was released over (as the last "dragging" saw it).
--- @return boolean taken true when the drop was taken
function ChatItemLinks.Dropped()
    local hover = g_hover
    ClearHover()
    if hover == nil or dmhub.Time() - hover.seen > 0.3 then
        return false
    end
    if hover.role == "target" then
        if hover.target.valid then
            hover.target:FireEvent("itemLinkDrop", hover.items)
        end
        return true
    end
    ChatItemLinks.Send(hover.items)
    return true
end

----------------------------------------------------------------------
--Opening links.

local function Unavailable(text)
    gui.ModalMessage{title = "Not available", message = text}
end

--- Opens what a link points at. It works for everyone who can read the chat:
--- a map opens on the table as if the Director had shared it, a journal entry
--- opens whatever folder it is in, a character or monster opens its Monster
--- Info stat block (which keeps to what the players have learned), and a
--- character with no stat block to learn (a hero) opens its sheet.
--- @param item ChatItemLink
function ChatItemLinks.Open(item)
    local kind = item.kind
    local id = item.id
    if kind == "map" then
        local map = game.GetMap(id)
        if map == nil or not map.valid then
            Unavailable("That map no longer exists.")
            return
        end
        Tabletop.OpenLinkedMap(id)
    elseif kind == "scene" then
        if Scenes.Get(id) == nil then
            Unavailable("That scene no longer exists.")
            return
        end
        Tabletop.OpenScene(id)
    elseif kind == "doc" then
        local entry = CustomDocument.FindJournalEntry(id)
        if entry == nil then
            Unavailable("That journal entry no longer exists.")
            return
        end
        CustomDocument.OpenContent(entry)
    elseif kind == "character" then
        local token = dmhub.GetCharacterById(id)
        if token == nil then
            Unavailable("That character no longer exists.")
            return
        end
        if MonsterKnowledge.KeyForToken(token) ~= nil then
            MonsterInfoDialog.Show(token)
        else
            token:ShowSheet()
        end
    elseif kind == "monster" then
        local monster = assets.monsters[id]
        if monster == nil or monster.info == nil then
            Unavailable("That monster is no longer in the bestiary.")
            return
        end
        MonsterInfoDialog.Show(monster.info)
    end
end

----------------------------------------------------------------------
--The chat message.

local KIND_NAMES = {
    map = "Map",
    scene = "Scene",
    character = "Character",
    monster = "Monster",
}

local LINK_HEIGHT = 44
local PICTURE_SIZE = 40

--- What a link shows: its name, a kind name ("Map"), a picture (or nil), an
--- icon for when there is no picture, and whether the picture is wide. Read
--- live, so a rename shows and each client sees only the names it may see.
--- Journal cards (RichItemLink.lua) use it too.
--- @param item ChatItemLink
--- @return {name: string, kind: string, image: nil|string, icon: nil|string, wide: nil|boolean}
function ChatItemLinks.Describe(item)
    local info = {name = item.name, kind = KIND_NAMES[item.kind] or "Item"}
    local kind = item.kind
    if kind == "map" then
        local map = game.GetMap(item.id)
        if map ~= nil and map.valid then
            info.name = map.description
            info.image = MapThumbnail.Image(map)
        end
        info.icon = "phosphor/map-trifold.png"
        info.wide = true
    elseif kind == "scene" then
        local scene = Scenes.Get(item.id)
        if scene ~= nil then
            info.name = Scenes.Name(item.id)
            if type(scene.image) == "string" and scene.image ~= "" and not FullscreenDisplay.IsVideo(scene.image) then
                info.image = scene.image
            end
        end
        info.icon = "phosphor/film-strip.png"
        info.wide = true
    elseif kind == "doc" then
        local entry = CustomDocument.FindJournalEntry(item.id)
        if entry ~= nil then
            info.kind = CustomDocument.JournalEntryKindName(entry)
            info.icon = CustomDocument.JournalEntryIcon(entry)
            info.image = CustomDocument.JournalEntryPicture(entry)
            pcall(function() info.name = entry.description end)
        end
        info.icon = info.icon or "phosphor/file-text.png"
    elseif kind == "character" then
        local token = dmhub.GetCharacterById(item.id)
        info.name = nil
        if token ~= nil then
            info.name = creature.GetTokenDescription(token)
            info.image = token.portrait
            if MonsterKnowledge.KeyForToken(token) ~= nil then
                info.kind = "Monster"
            end
        end
        info.icon = "phosphor/user.png"
    elseif kind == "monster" then
        local monster = assets.monsters[item.id]
        if monster ~= nil and monster.info ~= nil then
            info.name = monster.name
            info.image = monster.info.portrait
        end
        info.icon = "phosphor/user.png"
    end
    if type(info.name) ~= "string" or info.name == "" then
        info.name = "(unavailable)"
    end
    return info
end

local g_linkStyles = nil

local function LinkStyles()
    if g_linkStyles == nil then
        g_linkStyles = ThemeEngine.MergeTokens{
            {
                selectors = {"chatItemLink"},
                bgcolor = "clear",
            },
            {
                selectors = {"chatItemLink", "hover"},
                bgcolor = "@bgAlt",
                transitionTime = 0.1,
            },
            {
                selectors = {"chatItemLink", "press"},
                brightness = 0.8,
            },
            {
                selectors = {"chatItemLinkName"},
                color = "@fgStrong",
            },
            {
                selectors = {"chatItemLinkName", "parent:hover"},
                color = "@accent",
            },
        }
    end
    return g_linkStyles
end

--The link's picture, kept in shape inside a fixed slot; an icon when there
--is no picture.
local function LinkPicture(info)
    local width = cond(info.wide, math.floor(PICTURE_SIZE * 1.6), PICTURE_SIZE)
    local content
    if info.image ~= nil then
        content = gui.Panel{
            width = "auto",
            height = "auto",
            maxWidth = width,
            maxHeight = PICTURE_SIZE,
            autosizeimage = true,
            halign = "center",
            valign = "center",
            bgimage = info.image,
            bgcolor = "white",
            interactable = false,
        }
    else
        content = gui.Panel{
            width = 22,
            height = 22,
            halign = "center",
            valign = "center",
            bgimage = info.icon,
            bgcolor = "@fg",
            interactable = false,
        }
    end
    return gui.Panel{
        width = width,
        height = PICTURE_SIZE,
        valign = "center",
        interactable = false,
        content,
    }
end

local function LinkRow(item)
    local info = ChatItemLinks.Describe(item)
    return gui.Panel{
        classes = {"chatItemLink"},
        bgimage = true,
        width = "100%",
        height = LINK_HEIGHT,
        flow = "horizontal",
        hpad = 4,
        borderBox = true,
        press = function(element)
            ChatItemLinks.Open(item)
        end,
        hover = function(element)
            if item.kind == "doc" then
                CustomDocument.ShowJournalPreview(element, item.id, {hint = "Click to open"})
            else
                gui.Tooltip(string.format("Click to open %s", info.name))(element)
            end
        end,
        LinkPicture(info),
        gui.Panel{
            width = "100%-" .. (PICTURE_SIZE * 2),
            height = "auto",
            valign = "center",
            lmargin = 8,
            flow = "vertical",
            interactable = false,
            gui.Label{
                classes = {"sizeS", "chatItemLinkName"},
                width = "100%",
                height = "auto",
                bold = true,
                textWrap = false,
                text = info.name,
            },
            gui.Label{
                classes = {"sizeXxs", "fgMuted"},
                width = "100%",
                height = "auto",
                textWrap = false,
                text = info.kind,
            },
        },
    }
end

--- @class ChatItemLinkMessage: GameType
--- @field new fun(o?: table): ChatItemLinkMessage
--- @field items ChatItemLink[]
ChatItemLinkMessage = RegisterGameType("ChatItemLinkMessage")
ChatItemLinkMessage.channel = "chat"

function ChatItemLinkMessage:Render(message)
    --- @type Panel[]
    local children = {ChatAttachmentHeader(message)}
    for _, item in ipairs(self:try_get("items", {})) do
        if type(item) == "table" and type(item.kind) == "string" and type(item.id) == "string" then
            children[#children+1] = LinkRow(item)
        end
    end
    return gui.Panel{
        classes = {"chatMessage"},
        styles = LinkStyles(),
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
        linger = function(element)
            gui.Tooltip(DescribeServerTimestamp(message.timestamp))(element)
        end,
        children = children,
    }
end
