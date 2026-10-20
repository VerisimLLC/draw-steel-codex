local mod = dmhub.GetModLoading()

--Scene elements: what is placed on a scene from the Scenes library
--(ScenesPanel.lua): creature cards, pictures and videos, and sounds. A scene
--is a shared space: everyone looking at it -- in a tabletop scene window,
--maximized, or in the full-screen display -- sees the same things in the
--same places, and sees them move and resize while they are dragged.
--
--Sounds are the exception to "everyone sees": only those who control the
--table's audio (the Director and DJs, AudioCanControl) see them and switch
--them on and off. A sound that is on plays on every computer that has the
--scene open, and on no other (see "Scene sounds" below).
--
--Each scene keeps its elements in its own shared document,
--"sceneElements:<sceneid>":
--  edit          who may change the scene besides the Director: "none" (nobody),
--                "own" (players move and resize the cards of creatures they
--                control; the default) or "full" (players add, move, resize
--                and remove anything but sounds)
--  elements[id]  {kind, x, y, w, z, ...}: x, y the element's top-left and w
--                its width, as fractions of the scene's picture, so it sits on
--                the same spot of the art whatever size it is drawn at; z the
--                stacking order. A "creature" element has charid, a "media"
--                element (a journal picture or video) entryid, an "audio"
--                element key (the clip's asset id) and on/at/seq (see
--                SceneElements.ToggleSound).
--  z             the last z handed out
--A position is written to the document once, when its drag ends. While the
--drag lasts the dragger streams it to everyone else as a best-effort remote
--event (MOVE_EVENT, about 20 a second), and their copies ease towards it.
--
--Speech: whoever controls a card (and the Director) can make it say a line.
--The line is not saved anywhere: it goes to everyone as a reliable remote
--event (SPEECH_EVENT) and shows as a bubble above the card for a few seconds.
--
--How drops reach a scene: its layer (SceneElements.CreateLayer, mounted by
--FullscreenDisplay.CreateSceneView over the picture) is one of ChatItemLinks'
--item drop targets, so character and bestiary rows, table cards, journal
--rows and table items (pictures, videos, sounds), soundboard pads and other
--scenes' elements dropped on it arrive as "itemLinkDrop"; it is also the
--engine's token drop target, so tokens dragged off a map arrive as
--"dropTokens". A maximized scene under the UI is the table's background and
--takes no mouse; the tabletop's own drop handlers pass drops on it here
--(SceneElements.DropOnBackground, DropLinksOnBackground).

--- @class SceneElement
--- @field kind string
--- @field x number
--- @field y number
--- @field w number
--- @field z nil|number
--- @field charid nil|string
--- @field entryid nil|string
--- @field key nil|string
--- @field on nil|boolean
--- @field at nil|number
--- @field seq nil|integer

--- What a scene takes from a drag: a character, bestiary monster, journal
--- entry or sound link, perhaps carrying the scene and element it is being
--- moved out of.
--- @alias SceneLink {kind: string, id: string, fromScene: nil|string, fromElement: nil|string}

--- @class SceneElementKind
--- @field exists fun(el: SceneElement): boolean whether what it shows is still there
--- @field key fun(el: SceneElement): string what it shows; a scene holds one element per key, and a change rebuilds its panel
--- @field build fun(el: SceneElement): Panel, number, number its face at its own size, and that size
--- @field aspect fun(el: SceneElement): number its face's height / width
--- @field controls fun(el: SceneElement): boolean whether this user controls it ("own" scenes)
--- @field item fun(el: SceneElement): nil|ItemLinkDrop the link a drag of it carries
--- @field defaultWidth nil|number a new one's width (a share of the picture's width)
--- @field maxWidth nil|number the widest a resize makes it
--- @field speaks nil|boolean whether it can be made to say a line
--- @field sceneOnly nil|boolean its drag reaches only scenes (not chat or journals)
--- @field visible nil|fun(el: SceneElement): boolean whether this user sees it at all (default: everyone)
--- @field editable nil|fun(el: SceneElement): boolean who may move, resize and remove it, in place of the scene's edit mode
--- @field click nil|fun(el: SceneElement, sceneid: string, id: string) a click on it
--- @field tooltip nil|fun(el: SceneElement): string shown on hover
--- @field toTable nil|fun(el: SceneElement, screen: nil|Vector2) puts what it shows on the table (at the mouse, in screen pixels)
--- @field tableDragging nil|fun(el: SceneElement, element: Panel, toTable: boolean, drag: table) while it is dragged out of its scene
--- @field tableDragEnded nil|fun(el: SceneElement, element: Panel, drag: table) the drag ended

SceneElements = {}

--The class every scene's layer carries, so a drag that only scenes take
--(ChatItemLinks.Dragging's targetClass) can find it.
SceneElements.LAYER_CLASS = "sceneElementsLayer"

local MOVE_EVENT = "sceneElementMove"
local SPEECH_EVENT = "sceneElementSpeech"

--The longest line a card can say.
local SPEECH_LIMIT = 140

--A new card's width as a share of the picture's width, and the range a
--resize keeps to.
local DEFAULT_WIDTH = 0.12
local MIN_WIDTH = 0.04
local MAX_WIDTH = 0.6

--Several cards dropped at once step down-right by this much.
local CARD_STEP = 0.025

--The picture's height / width when a scene has none (or it has not loaded).
SceneElements.NO_ART_ASPECT = 9 / 16

--Someone else's streamed position is followed this long after their last
--message, or, after the message that ends their drag, until the document
--has the drop (at most FINAL_SECONDS).
local LIVE_SECONDS = 0.5
local FINAL_SECONDS = 3
local SEND_INTERVAL = 0.05

--This client's id on the move events, so it skips its own echo.
local g_clientId = dmhub.GenerateGuid()

local function DocId(sceneid)
    return "sceneElements:" .. sceneid
end

local function Doc(sceneid)
    return mod:GetDocumentSnapshot(DocId(sceneid))
end

--- The path of a scene's elements document, for monitorGame.
--- @param sceneid string
--- @return string
function SceneElements.DocPath(sceneid)
    return Doc(sceneid).path
end

--options: CompleteChange's (e.g. {undoable = false}).
local function Change(sceneid, description, fn, options)
    local doc = Doc(sceneid)
    doc:BeginChange()
    if type(doc.data.elements) ~= "table" then
        doc.data.elements = {}
    end
    fn(doc.data)
    doc:CompleteChange(description, options)
end

local function Clamp(v, lo, hi)
    if hi < lo then
        return lo
    end
    return math.max(lo, math.min(hi, v))
end

----------------------------------------------------------------------
--Who may change a scene.

--- The edit modes, in the order the Director's menu lists them.
SceneElements.EDIT_MODES = {
    {
        id = "none",
        text = "Only the Director",
        icon = "phosphor/lock-simple-fill.png",
        tip = "Only you can change what is in this scene",
    },
    {
        id = "own",
        text = "Players control their heroes",
        icon = "phosphor/user-fill.png",
        tip = "Players can move and resize their own heroes in this scene, but not add or remove anything",
    },
    {
        id = "full",
        text = "Players have full control",
        icon = "phosphor/users-three.png",
        tip = "Players can add, move, resize and remove anything in this scene",
    },
}

--- @param sceneid string
--- @return string mode "none", "own" or "full"
function SceneElements.EditMode(sceneid)
    local mode = Doc(sceneid).data.edit
    if mode == "none" or mode == "full" then
        return mode
    end
    return "own"
end

--- @param sceneid string
--- @return {id: string, text: string, icon: string, tip: string}
function SceneElements.EditModeInfo(sceneid)
    local mode = SceneElements.EditMode(sceneid)
    for _, info in ipairs(SceneElements.EDIT_MODES) do
        if info.id == mode then
            return info
        end
    end
    return SceneElements.EDIT_MODES[2]
end

--- The Director sets who may change the scene.
--- @param sceneid string
--- @param mode string
function SceneElements.SetEditMode(sceneid, mode)
    if not dmhub.isDM or SceneElements.EditMode(sceneid) == mode then
        return
    end
    Change(sceneid, "Change who can edit the scene", function(data)
        data.edit = mode
    end)
end

--- Whether this user may put things into the scene (and take them out).
--- @param sceneid string
--- @return boolean
function SceneElements.CanAdd(sceneid)
    return dmhub.isDM or SceneElements.EditMode(sceneid) == "full"
end

SceneElements.CanRemove = SceneElements.CanAdd

----------------------------------------------------------------------
--Scene sounds: the state an "audio" element is in. A sound that is on plays
--on every computer that has the scene open, each playing the clip itself
--(asset:Play(), never broadcast), so whoever does not have the scene open
--hears nothing. ToggleSound switches it, stamping at (server time) and
--bumping seq: a looping clip plays for as long as it is on, any other until
--its length has passed. Someone who opens the scene part-way through joins
--at the same point as everyone else. (The player itself is "Playing scene
--sounds", after the layer.)

--- The clip an "audio" element plays, or nil once it is gone.
--- @param el SceneElement
--- @return nil|AudioAssetLua
local function SoundAsset(el)
    if type(el.key) ~= "string" then
        return nil
    end
    local asset = assets.audioTable[el.key]
    if asset == nil or asset.hidden then
        return nil
    end
    return asset
end

--- Whether a sound should be heard now, and how far into its clip.
--- @param el SceneElement
--- @return boolean playing, number offset seconds
local function SoundState(el)
    if el.on ~= true then
        return false, 0
    end
    local asset = SoundAsset(el)
    if asset == nil then
        return false, 0
    end
    local elapsed = math.max(0, dmhub.serverTime - (tonumber(el.at) or dmhub.serverTime))
    local duration = tonumber(asset.duration) or 0
    if asset.loop == true then
        if duration > 0.1 then
            return true, elapsed % duration
        end
        return true, 0
    end
    if duration > 0.1 then
        return elapsed < duration, elapsed
    end
    --a clip whose length is not known yet: only just after it was switched on.
    return elapsed < 2, 0
end

--- Switches a scene's sound on (from the start of its clip) or off, for
--- everyone who has the scene open.
--- @param sceneid string
--- @param id string the element id
function SceneElements.ToggleSound(sceneid, id)
    if not AudioCanControl() then
        return
    end
    Change(sceneid, "Switch a scene sound", function(data)
        local el = data.elements[id]
        if type(el) ~= "table" or el.kind ~= "audio" then
            return
        end
        ---@cast el SceneElement
        if SoundState(el) then
            el.on = false
        else
            el.on = true
            el.at = dmhub.serverTime
            el.seq = (tonumber(el.seq) or 0) + 1
        end
    end, {undoable = false})
end

----------------------------------------------------------------------
--Element kinds.

--- @type table<string, SceneElementKind>
SceneElements.kinds = {}

--A creature card dragged out over the table shows the card a drop there makes.
local function EndCardPreview(drag)
    if drag.preview ~= nil and drag.preview.valid then
        drag.preview:DestroySelf()
    end
    drag.preview = nil
end

SceneElements.kinds.creature = {
    exists = function(el)
        return type(el.charid) == "string" and dmhub.GetCharacterById(el.charid) ~= nil
    end,
    key = function(el)
        return tostring(el.charid)
    end,
    build = function(el)
        local tok = dmhub.GetCharacterById(el.charid)
        local w, h = Tabletop.CardSize()
        return Tabletop.CardFace(el.charid, tok), w, h
    end,
    aspect = function(el)
        local w, h = Tabletop.CardSize()
        return h / w
    end,
    controls = function(el)
        local tok = dmhub.GetCharacterById(el.charid)
        return tok ~= nil and tok.canControlAsUser == true
    end,
    item = function(el)
        return ChatItemLinks.CharacterItem(el.charid)
    end,
    speaks = true,
    toTable = function(el, screen)
        if screen == nil then
            Tabletop.OpenCard(el.charid, {placed = true})
            return
        end
        local x, y = Tabletop.CardDropPlacement(screen.x, screen.y, 1)
        Tabletop.OpenCard(el.charid, {x = x, y = y, placed = true})
    end,
    tableDragging = function(el, element, toTable, drag)
        if not toTable then
            EndCardPreview(drag)
            return
        end
        if drag.preview == nil or not drag.preview.valid then
            drag.preview = Tabletop.BuildCardPreview(el.charid)
        end
        if drag.preview ~= nil then
            local mouse = dmhub.mouseScreenPosition
            drag.preview.x, drag.preview.y = Tabletop.CardDropPlacement(mouse.x, mouse.y, 1)
            drag.preview:SetAsLastSibling()
        end
    end,
    tableDragEnded = function(el, element, drag)
        EndCardPreview(drag)
    end,
}

--A journal picture or video ("image" entries; a video is one too). The
--entry's id is also its image's id.
local function MediaEntry(el)
    if type(el.entryid) ~= "string" then
        return nil
    end
    local entry = CustomDocument.FindJournalEntry(el.entryid)
    if entry == nil or entry.nodeType ~= "image" then
        return nil
    end
    return entry
end

--The picture's height / width: the file's own shape when the table recorded
--it (TableMedia, for files dropped from the desktop), else the entry's.
local function MediaAspect(el)
    local aspect = nil
    local media = TableMedia.Info(el.entryid)
    if media ~= nil and media.width > 0 and media.height > 0 then
        aspect = media.height / media.width
    else
        local entry = MediaEntry(el)
        if entry ~= nil then
            local _, entryAspect = CustomDocument.JournalEntryPicture(entry)
            aspect = entryAspect
        end
    end
    return Clamp(aspect or SceneElements.NO_ART_ASPECT, 0.25, 4)
end

--A picture's face is built this wide (the scene scales it), inside a thin frame.
local MEDIA_WIDTH = 240
local MEDIA_INSET = 2

SceneElements.kinds.media = {
    exists = function(el)
        return MediaEntry(el) ~= nil
    end,
    key = function(el)
        return tostring(el.entryid)
    end,
    aspect = MediaAspect,
    build = function(el)
        local w = MEDIA_WIDTH
        local h = math.floor(w * MediaAspect(el))
        --a video loops with no sound, as a scene's own video does: a play bar
        --would let everyone's copy drift apart (David, 2026-10-18).
        local video = TableMedia.IsVideo(el.entryid)
        local face = gui.Panel{
            classes = {"sceneElementMedia"},
            bgimage = "panels/square.png",
            width = w,
            height = h,
            flow = "none",
            interactable = false,
            gui.Panel{
                width = w - MEDIA_INSET * 2,
                height = h - MEDIA_INSET * 2,
                halign = "center",
                valign = "center",
                bgimage = cond(video, nil, el.entryid),
                bgcolor = "white",
                cornerRadius = 5,
                interactable = false,
                create = function(element)
                    if video then
                        --its own looping player ("###" gives this panel its own instance).
                        element.bgimageStreamed = el.entryid .. "###LOOP" .. dmhub.GenerateGuid()
                    end
                end,
            },
        }
        return face, w, h
    end,
    controls = function(el)
        return false
    end,
    item = function(el)
        return ChatItemLinks.DocItem(el.entryid)
    end,
    defaultWidth = 0.25,
    maxWidth = 1,
    click = function(el)
        local entry = MediaEntry(el)
        if entry ~= nil then
            CustomDocument.OpenContent(entry)
        end
    end,
    toTable = function(el, screen)
        Tabletop.OpenDocItem(el.entryid, {screen = screen, placed = true})
    end,
    --over the bare table the element steps aside and the table item a drop
    --there makes follows the mouse, as for a journal row.
    tableDragging = function(el, element, toTable)
        if toTable then
            Tabletop.JournalRowDragging(element, el.entryid)
        else
            Tabletop.JournalRowDragEnded(element)
        end
    end,
    tableDragEnded = function(el, element)
        Tabletop.JournalRowDragEnded(element)
    end,
}

--A sound's face is built this size (the scene scales it).
local SOUND_WIDTH = 168
local SOUND_HEIGHT = 56

--The sound's tile: its colour, a speaker, its name and whether it is playing.
--It lights while the sound plays (refreshElement, from the layer).
local function SoundFace(el)
    local name, color = AudioClipLook(SoundAsset(el))
    local status = gui.Label{
        classes = {"sceneSoundStatus"},
        width = "100%",
        height = "auto",
        fontSize = 11,
        text = "Off",
        interactable = false,
    }
    return gui.Panel{
        classes = {"sceneSound"},
        bgimage = "panels/square.png",
        width = SOUND_WIDTH,
        height = SOUND_HEIGHT,
        flow = "horizontal",
        hpad = 8,
        borderBox = true,
        interactable = false,
        refreshElement = function(element, current)
            local playing = SoundState(current)
            element:SetClassTree("sceneSoundOn", playing)
            local asset = SoundAsset(current)
            if not playing then
                status.text = "Off - players can't see this"
            elseif asset ~= nil and asset.loop == true then
                status.text = "Looping"
            else
                status.text = "Playing"
            end
        end,
        create = function(element)
            element:FireEvent("refreshElement", el)
        end,
        --the clip's colour, as on the soundboard.
        gui.Panel{
            width = 4,
            height = SOUND_HEIGHT - 16,
            valign = "center",
            rmargin = 8,
            bgimage = "panels/square.png",
            bgcolor = color,
            cornerRadius = 2,
            interactable = false,
        },
        gui.Panel{
            classes = {"sceneSoundIcon"},
            bgimage = "phosphor/speaker-high-fill.png",
            width = 22,
            height = 22,
            valign = "center",
            rmargin = 8,
            interactable = false,
        },
        gui.Panel{
            width = SOUND_WIDTH - 16 - 12 - 30,
            height = "auto",
            valign = "center",
            flow = "vertical",
            interactable = false,
            gui.Label{
                classes = {"sceneSoundName"},
                width = "100%",
                height = "auto",
                fontSize = 13,
                bold = true,
                textOverflow = "ellipsis",
                textWrap = false,
                text = name,
                interactable = false,
            },
            status,
        },
    }
end

SceneElements.kinds.audio = {
    exists = function(el)
        return SoundAsset(el) ~= nil
    end,
    key = function(el)
        return tostring(el.key)
    end,
    build = function(el)
        return SoundFace(el), SOUND_WIDTH, SOUND_HEIGHT
    end,
    aspect = function(el)
        return SOUND_HEIGHT / SOUND_WIDTH
    end,
    controls = function(el)
        return false
    end,
    item = function(el)
        return {kind = "audio", id = el.key}
    end,
    defaultWidth = 0.14,
    --a sound is not a chat link or a journal tag: only scenes take it.
    sceneOnly = true,
    --the players never see a scene's sounds; whoever controls the table's
    --audio does, whatever the scene's edit mode.
    visible = function(el)
        return AudioCanControl()
    end,
    editable = function(el)
        return AudioCanControl()
    end,
    click = function(el, sceneid, id)
        SceneElements.ToggleSound(sceneid, id)
    end,
    tooltip = function(el)
        return "Click to play it for everyone who has this scene open. Players can't see it."
    end,
    toTable = function(el, screen)
        Tabletop.OpenItem("audio", el.key, {screen = screen})
    end,
    tableDragging = function(el, element, toTable)
        if toTable then
            Tabletop.ItemRowDragging(element, "audio", el.key)
        else
            Tabletop.ItemRowDragEnded(element)
        end
    end,
    tableDragEnded = function(el, element)
        Tabletop.ItemRowDragEnded(element)
    end,
}

--- Whether this user sees the element at all.
--- @param el SceneElement
--- @return boolean
function SceneElements.Visible(el)
    local kind = SceneElements.kinds[el.kind]
    return kind ~= nil and (kind.visible == nil or kind.visible(el))
end

--- Whether this user may move and resize the element.
--- @param sceneid string
--- @param el SceneElement
--- @return boolean
function SceneElements.CanChange(sceneid, el)
    local kind = SceneElements.kinds[el.kind]
    if kind ~= nil and kind.editable ~= nil then
        return kind.editable(el)
    end
    if dmhub.isDM then
        return true
    end
    local mode = SceneElements.EditMode(sceneid)
    if mode == "full" then
        return true
    end
    return mode == "own" and kind ~= nil and kind.controls(el)
end

--- Whether this user may take the element out of the scene.
--- @param sceneid string
--- @param el SceneElement
--- @return boolean
function SceneElements.CanRemoveElement(sceneid, el)
    local kind = SceneElements.kinds[el.kind]
    if kind ~= nil and kind.editable ~= nil then
        return kind.editable(el)
    end
    return SceneElements.CanRemove(sceneid)
end

--- Whether this user may make the element speak: the Director, or whoever
--- controls it, whatever the scene's edit mode. Only creatures speak.
--- @param el SceneElement
--- @return boolean
function SceneElements.CanSpeak(el)
    local kind = SceneElements.kinds[el.kind]
    if kind == nil or not kind.speaks then
        return false
    end
    return dmhub.isDM or kind.controls(el)
end

local function ValidElement(el)
    if type(el) ~= "table" then
        return false
    end
    local kind = SceneElements.kinds[el.kind]
    return kind ~= nil and type(el.x) == "number" and type(el.y) == "number" and type(el.w) == "number" and kind.exists(el)
end

--- The scene's elements that can be drawn, by id.
--- @param sceneid string
--- @return table<string, SceneElement>
function SceneElements.Elements(sceneid)
    local out = {}
    local elements = Doc(sceneid).data.elements
    if type(elements) == "table" then
        for id, el in pairs(elements) do
            if ValidElement(el) then
                out[id] = el
            end
        end
    end
    return out
end

--- @param sceneid string
--- @return integer
function SceneElements.Count(sceneid)
    local n = 0
    for _ in pairs(SceneElements.Elements(sceneid)) do
        n = n + 1
    end
    return n
end

----------------------------------------------------------------------
--Changing a scene.

--What scenes just took, by "<link kind>:<id>": a table card, picture or
--sound dropped on a scene moves in, so its drag asks here whether to leave
--the table (Took).
local g_took = {}

--- Whether a scene took this from a drop in the last half second.
--- @param kind string the link's kind: "character", "doc" or "audio"
--- @param id string
--- @return boolean
function SceneElements.Took(kind, id)
    local t = g_took[kind .. ":" .. tostring(id)]
    return t ~= nil and dmhub.Time() - t < 0.5
end

--- @param charid string
--- @return boolean
function SceneElements.TookCharacter(charid)
    return SceneElements.Took("character", charid)
end

--The element already showing this (a scene holds one per key), if any.
local function ElementFor(data, kindName, key)
    local kind = SceneElements.kinds[kindName]
    for id, el in pairs(data.elements) do
        if type(el) == "table" and el.kind == kindName and kind.key(el) == key then
            return id
        end
    end
    return nil
end

--- Puts elements into a scene, the first centred on (cx, cy) (fractions of
--- the picture) and the rest stepping down-right. One already in the scene
--- (the same kind showing the same thing) moves there instead, keeping its
--- size and state.
--- @param sceneid string
--- @param adds SceneElement[] each with its kind and what it shows; the place is filled in here
--- @param cx number
--- @param cy number
--- @param artAspect nil|number the picture's height / width
local function AddElements(sceneid, adds, cx, cy, artAspect)
    if #adds == 0 then
        return
    end
    artAspect = artAspect or SceneElements.NO_ART_ASPECT
    Change(sceneid, "Add to scene", function(data)
        for i, add in ipairs(adds) do
            local kind = SceneElements.kinds[add.kind]
            local id = ElementFor(data, add.kind, kind.key(add)) or dmhub.GenerateGuid()
            local old = data.elements[id]
            --its height as a share of the picture's, per unit of width.
            local stretch = kind.aspect(add) / artAspect
            local w = kind.defaultWidth or DEFAULT_WIDTH
            if type(old) == "table" and type(old.w) == "number" then
                w = old.w
            end
            --never taller (or wider) than the picture.
            w = math.min(w, 1, 1 / stretch)
            local h = w * stretch
            data.z = (tonumber(data.z) or 0) + 1
            local el = {}
            if type(old) == "table" then
                for k, v in pairs(old) do
                    el[k] = v
                end
            end
            for k, v in pairs(add) do
                el[k] = v
            end
            el.x = Clamp(cx - w / 2 + (i - 1) * CARD_STEP, 0, 1 - w)
            el.y = Clamp(cy - h / 2 + (i - 1) * CARD_STEP, 0, 1 - h)
            el.w = w
            el.z = data.z
            data.elements[id] = el
        end
    end)
end

--- Puts characters into a scene, the first centred on (cx, cy) (fractions of
--- the picture) and the rest stepping down-right. A character already in the
--- scene moves there instead: a scene holds one card per character.
--- @param sceneid string
--- @param charids string[]
--- @param cx number
--- @param cy number
--- @param artAspect nil|number the picture's height / width
function SceneElements.AddCreatures(sceneid, charids, cx, cy, artAspect)
    local adds = {}
    for _, charid in ipairs(charids) do
        adds[#adds+1] = {kind = "creature", charid = charid, x = 0, y = 0, w = 0}
        g_took["character:" .. charid] = dmhub.Time()
    end
    AddElements(sceneid, adds, cx, cy, artAspect)
end

--- The Director drops bestiary creatures into a scene: each is created with
--- no map (as a drop on the bare table does) and enters the scene once the
--- game has it.
--- @param sceneid string
--- @param monsterids string[]
--- @param cx number
--- @param cy number
--- @param artAspect nil|number
function SceneElements.AddMonsters(sceneid, monsterids, cx, cy, artAspect)
    if not dmhub.isDM then
        return
    end
    for i, monsterid in ipairs(monsterids) do
        local tok = game.SpawnTokenFromBestiaryLocally(monsterid, nil)
        if tok ~= nil then
            tok:UploadToken()
            local charid = tok.charid
            local x = cx + (i - 1) * CARD_STEP
            local y = cy + (i - 1) * CARD_STEP
            dmhub.Coroutine(function()
                for _ = 1, 100 do
                    if mod.unloaded then
                        return
                    end
                    if dmhub.GetCharacterById(charid) ~= nil then
                        SceneElements.AddCreatures(sceneid, {charid}, x, y, artAspect)
                        return
                    end
                    coroutine.yield(0.05)
                end
            end)
        end
    end
    game.UpdateCharacterTokens()
end

--- Where an element is: its top-left and width (fractions of the picture).
--- It also comes to the front.
--- @param sceneid string
--- @param id string
--- @param x number
--- @param y number
--- @param w number
function SceneElements.Place(sceneid, id, x, y, w)
    Change(sceneid, "Move in scene", function(data)
        local el = data.elements[id]
        if type(el) ~= "table" then
            return
        end
        data.z = (tonumber(data.z) or 0) + 1
        el.x = x
        el.y = y
        el.w = w
        el.z = data.z
    end)
end

--- @param sceneid string
--- @param id string
function SceneElements.Remove(sceneid, id)
    Change(sceneid, "Remove from scene", function(data)
        data.elements[id] = nil
    end)
end

--- The element a dragged link would make, at no place yet; nil for a
--- bestiary monster (it becomes a character first) or anything a scene does
--- not take (a map, a document or PDF, a variant pool).
--- @param link SceneLink
--- @return nil|SceneElement
local function ElementOfLink(link)
    local el = nil
    if link.kind == "character" then
        el = {kind = "creature", charid = link.id, x = 0, y = 0, w = 0}
    elseif link.kind == "doc" then
        el = {kind = "media", entryid = link.id, x = 0, y = 0, w = 0}
    elseif link.kind == "audio" then
        el = {kind = "audio", key = link.id, x = 0, y = 0, w = 0}
    end
    if el == nil or not SceneElements.kinds[el.kind].exists(el) then
        return nil
    end
    return el
end

--- Whether this user may put what a link names into the scene (and, for an
--- element dragged out of another scene, take it out of that one).
--- @param sceneid string
--- @param link any
--- @return boolean
local function CanTake(sceneid, link)
    if type(link) ~= "table" or type(link.id) ~= "string" or link.fromScene == sceneid then
        return false
    end
    ---@cast link SceneLink
    if link.kind == "monster" then
        return SceneElements.CanAdd(sceneid) and assets.monsters[link.id] ~= nil
    end
    local el = ElementOfLink(link)
    if el == nil then
        return false
    end
    local kind = SceneElements.kinds[el.kind]
    local allowed
    if kind.editable ~= nil then
        allowed = kind.editable(el)
    else
        allowed = SceneElements.CanAdd(sceneid)
    end
    if not allowed then
        return false
    end
    if link.fromScene ~= nil then
        local from = Doc(link.fromScene).data.elements
        local old = type(from) == "table" and type(link.fromElement) == "string" and from[link.fromElement] or nil
        return type(old) == "table" and SceneElements.CanRemoveElement(link.fromScene, old)
    end
    return true
end

--- Puts what dragged links name into a scene, the first centred on (cx, cy):
--- characters, bestiary monsters, journal pictures and videos, sounds. One
--- dragged out of another scene leaves that scene. Links this user may not
--- add are skipped.
--- @param sceneid string
--- @param links any[] SceneLinks (anything else is skipped)
--- @param cx number
--- @param cy number
--- @param artAspect nil|number the picture's height / width
--- @return boolean taken whether the scene took anything
function SceneElements.TakeLinks(sceneid, links, cx, cy, artAspect)
    local adds = {}
    local monsterids = {}
    local now = dmhub.Time()
    for _, link in pairs(links or {}) do
        if CanTake(sceneid, link) then
            ---@cast link SceneLink
            if link.fromScene ~= nil and link.fromElement ~= nil then
                SceneElements.Remove(link.fromScene, link.fromElement)
            end
            if link.kind == "monster" then
                monsterids[#monsterids+1] = link.id
            else
                adds[#adds+1] = ElementOfLink(link)
                g_took[link.kind .. ":" .. link.id] = now
            end
        end
    end
    AddElements(sceneid, adds, cx, cy, artAspect)
    SceneElements.AddMonsters(sceneid, monsterids, cx, cy, artAspect)
    return #adds > 0 or #monsterids > 0
end

----------------------------------------------------------------------
--Live positions while someone drags.

--sceneid|id -> {x, y, w, t, final}
local g_live = {}

local function LiveKey(sceneid, id)
    return sceneid .. "|" .. id
end

local function SendMove(sceneid, id, x, y, w, final)
    --the last message must arrive (it hands over to the document), so it
    --goes through the game server; the stream is best-effort. A scene is not
    --on any map, so it reaches everyone, whatever map they are on.
    dmhub.BroadcastRemoteEvent(MOVE_EVENT, LiveKey(sceneid, id), {
        gameid = dmhub.gameid,
        from = g_clientId,
        sceneid = sceneid,
        id = id,
        x = x,
        y = y,
        w = w,
        final = final == true,
    }, final == true, true)
end

dmhub.RegisterRemoteEvent(MOVE_EVENT, function(info)
    if mod.unloaded or type(info) ~= "table" or info.gameid ~= dmhub.gameid or info.from == g_clientId then
        return
    end
    if type(info.sceneid) ~= "string" or type(info.id) ~= "string" then
        return
    end
    local x, y, w = tonumber(info.x), tonumber(info.y), tonumber(info.w)
    if x == nil or y == nil or w == nil then
        return
    end
    g_live[LiveKey(info.sceneid, info.id)] = {x = x, y = y, w = w, t = dmhub.Time(), final = info.final == true}
end)

--Where an element should be drawn now: someone's live drag, or the document.
local function TargetOf(sceneid, id, el)
    local key = LiveKey(sceneid, id)
    local live = g_live[key]
    if live ~= nil then
        local age = dmhub.Time() - live.t
        local landed = math.abs(el.x - live.x) < 1e-4 and math.abs(el.y - live.y) < 1e-4 and math.abs(el.w - live.w) < 1e-4
        if age < LIVE_SECONDS or (live.final and age < FINAL_SECONDS and not landed) then
            return live.x, live.y, live.w
        end
        g_live[key] = nil
    end
    return el.x, el.y, el.w
end

----------------------------------------------------------------------
--Speech bubbles.

--sceneid|id -> {text, t, dur}: what each card is saying, kept here (not per
--layer) so every view of the scene shows the same bubble.
local g_speech = {}

local function SetSpeech(sceneid, id, text)
    --long lines stay up longer, so they can be read.
    g_speech[LiveKey(sceneid, id)] = {text = text, t = dmhub.Time(), dur = Clamp(3 + #text * 0.06, 4, 12)}
end

--- Makes a card in a scene say a line: a bubble above it, for everyone.
--- @param sceneid string
--- @param id string the element id
--- @param text string
function SceneElements.Say(sceneid, id, text)
    text = trim(text or ""):sub(1, SPEECH_LIMIT)
    if text == "" then
        return
    end
    SetSpeech(sceneid, id, text)
    dmhub.BroadcastRemoteEvent(SPEECH_EVENT, LiveKey(sceneid, id), {
        gameid = dmhub.gameid,
        from = g_clientId,
        sceneid = sceneid,
        id = id,
        text = text,
    }, true, true)
end

dmhub.RegisterRemoteEvent(SPEECH_EVENT, function(info)
    if mod.unloaded or type(info) ~= "table" or info.gameid ~= dmhub.gameid or info.from == g_clientId then
        return
    end
    if type(info.sceneid) ~= "string" or type(info.id) ~= "string" or type(info.text) ~= "string" then
        return
    end
    local text = trim(info.text):sub(1, SPEECH_LIMIT)
    if text ~= "" then
        SetSpeech(info.sceneid, info.id, text)
    end
end)

--- What a card is saying now, and how far its bubble is shown: it pops in
--- over its first 0.12s and shrinks away over its last 0.3s (1 = fully).
--- @return nil|string, number
local function SpeechOf(sceneid, id)
    local key = LiveKey(sceneid, id)
    local s = g_speech[key]
    if s == nil then
        return nil, 0
    end
    local age = dmhub.Time() - s.t
    local left = s.dur - age
    if left <= 0 then
        g_speech[key] = nil
        return nil, 0
    end
    return s.text, Clamp(math.min(age / 0.12, left / 0.3), 0, 1)
end

----------------------------------------------------------------------
--Emotes: a few seconds of animation on a card (alarmed, scared, ...),
--sent to everyone like speech (EMOTE_EVENT) and not saved.
--
--Each emote draws its effects in a panel the card's native size laid over
--the card (so it is authored in the card's own pixels, w x h), and may jolt
--the card's face: update returns that offset, also in card pixels.

local EMOTE_EVENT = "sceneElementEmote"
local EMOTE_SECONDS = 5

--- @class SceneEmote
--- @field id string
--- @field text string
--- @field icon string
--- @field build fun(fx: Panel, w: number, h: number, card: SceneEmoteCard): table its parts, handed back to update
--- @field update fun(st: table, t: number, w: number, h: number): number, number the face's offset t seconds in
--- @field finish nil|fun(st: table) undoes what it did to the card itself

--- The card an emote plays on.
--- @class SceneEmoteCard
--- @field face Panel the card's face
--- @field el SceneElement

local function Rand()
    return math.random() * 2 - 1
end

--A picture or text in a square of size s, with a dark copy behind it so it
--reads on any art. Placed by its top-left (x, y) in the card's pixels; it
--scales and rotates about its centre. args.squash < 1 squeezes a picture's
--height (before any rotation).
local function Sprite(fx, s, args)
    local function Part(color, off)
        if args.text ~= nil then
            return gui.Label{
                text = args.text,
                fontFace = "Berling",
                bold = true,
                fontSize = args.fontSize or s * 0.8,
                color = color,
                width = s,
                height = s,
                halign = "center",
                valign = "center",
                textAlignment = "center",
                x = off,
                y = off,
                interactable = false,
            }
        end
        return gui.Panel{
            bgimage = args.image,
            bgcolor = color,
            width = s,
            height = s * (args.squash or 1),
            halign = "center",
            valign = "center",
            x = off,
            y = off,
            interactable = false,
        }
    end
    local children = {}
    if args.shadow ~= false then
        children[#children+1] = Part("#1d1915b0", math.max(1.5, s * 0.04))
    end
    children[#children+1] = Part(args.color or "white", 0)
    local panel = gui.Panel{
        halign = "left",
        valign = "top",
        x = args.x or 0,
        y = args.y or 0,
        width = s,
        height = s,
        flow = "none",
        interactable = false,
        children = children,
    }
    fx:AddChild(panel)
    return panel
end

--A colour wash over the whole card.
local function Tint(fx, w, h, color)
    local panel = gui.Panel{
        halign = "left",
        valign = "top",
        width = w,
        height = h,
        bgimage = "panels/square.png",
        bgcolor = color,
        cornerRadius = w * 0.05,
        opacity = 0,
        interactable = false,
    }
    fx:AddChild(panel)
    return panel
end

--Grows to 1.25 and settles to 1 over its first 0.22 seconds.
local function Pop(t)
    if t < 0.12 then
        return math.max(0.01, t / 0.12 * 1.25)
    elseif t < 0.22 then
        return 1.25 - (t - 0.12) / 0.1 * 0.25
    end
    return 1
end

--How far (0-1) into a repeating cycle of `period` seconds, started `delay`
--seconds in; nil before it starts.
local function Cycle(t, period, delay)
    local u = (t - (delay or 0)) / period
    if u < 0 then
        return nil
    end
    return u % 1
end

--- The emotes, in the order the menu lists them.
--- @type SceneEmote[]
SceneElements.EMOTES = {
    {
        --three yellow dashes burst out above the card, which jolts.
        id = "alarmed",
        text = "Alarmed",
        icon = "phosphor/warning-fill.png",
        build = function(fx, w, h)
            local dashes = {}
            for i, a in ipairs({-38, 0, 38}) do
                local dw, dh = w * 0.06, w * 0.19
                local r = w * 0.2
                local cx = w / 2 + r * math.sin(math.rad(a))
                local cy = -w * 0.05 - r * math.cos(math.rad(a))
                local dash = gui.Panel{
                    halign = "left",
                    valign = "top",
                    x = cx - dw / 2,
                    y = cy - dh / 2,
                    width = dw,
                    height = dh,
                    bgimage = "panels/square.png",
                    bgcolor = "#ffd23a",
                    cornerRadius = dw / 2,
                    borderWidth = 2,
                    borderColor = "#2a2116",
                    rotate = -a,
                    scale = 0.01,
                    interactable = false,
                }
                fx:AddChild(dash)
                dashes[i] = dash
            end
            return {dashes = dashes}
        end,
        update = function(st, t, w, h)
            local k = Pop(t)
            for _, dash in ipairs(st.dashes) do
                dash.selfStyle.scale = k
            end
            if t < 0.18 then
                return 0, -w * 0.05 * math.sin(t / 0.18 * math.pi)
            end
            return 0, 0
        end,
    },
    {
        --the card trembles, with thin white squiggles wobbling at its edges
        --and a bead of sweat running down.
        id = "scared",
        text = "Scared",
        icon = "phosphor/smiley-nervous-fill.png",
        build = function(fx, w, h)
            local lines = {}
            local s = w * 0.22
            for side = -1, 1, 2 do
                for j, fy in ipairs({0.25, 0.5, 0.75}) do
                    local bx = cond(side < 0, -s * 0.72, w - s * 0.28)
                    local by = h * fy - s / 2 + cond(side < 0, 0, h * 0.08)
                    --squashed to half height, then stood upright: the wave's
                    --swing is half the icon's.
                    local sprite = Sprite(fx, s, {image = "phosphor/wave-sine-light.png", squash = 0.5, x = bx, y = by})
                    sprite.selfStyle.rotate = 90
                    lines[#lines+1] = {panel = sprite, bx = bx, side = side, phase = j * 1.7 + cond(side < 0, 0, 0.8)}
                end
            end
            local drop = Sprite(fx, w * 0.11, {image = "phosphor/drop-fill.png", color = "#a8dcff", x = w * 0.8, y = h * 0.05})
            return {lines = lines, drop = drop}
        end,
        update = function(st, t, w, h)
            for _, line in ipairs(st.lines) do
                line.panel.x = line.bx + line.side * w * 0.035 * (0.5 + 0.5 * math.sin(t * 9 + line.phase))
            end
            local u = Cycle(t, 1.6) or 0
            st.drop.y = h * (0.05 + 0.14 * u)
            st.drop.selfStyle.scale = math.max(0.01, math.min(1, (1 - u) * 4, u * 8))
            return Rand() * w * 0.014, Rand() * w * 0.007
        end,
    },
    {
        --the card shakes violently and its portrait flushes red (a card
        --with no portrait gets a red wash instead).
        id = "rage",
        text = "Rage",
        icon = "phosphor/smiley-angry-fill.png",
        build = function(fx, w, h, card)
            local portrait = nil
            local tok = card.el.charid ~= nil and dmhub.GetCharacterById(card.el.charid) or nil
            if tok ~= nil then
                pcall(function() portrait = tok.offTokenPortrait end)
            end
            if portrait ~= nil and portrait ~= "" and card.face.valid then
                return {face = card.face}
            end
            return {tint = Tint(fx, w, h, "#ff2a10")}
        end,
        update = function(st, t, w, h)
            local ramp = math.min(1, t / 0.3)
            local pulse = 0.5 + 0.5 * math.sin(t * 11)
            if st.face ~= nil then
                --the portrait is drawn through its bgcolor (white = as is),
                --so this multiplies it towards red.
                if st.face.valid then
                    local gb = math.floor(255 - ramp * (150 + 50 * pulse))
                    st.face.selfStyle.bgcolor = string.format("#ff%02x%02x", gb, gb)
                end
            else
                st.tint.selfStyle.opacity = ramp * (0.34 + 0.14 * (pulse * 2 - 1))
            end
            return Rand() * w * 0.04, Rand() * w * 0.025
        end,
        finish = function(st)
            if st.face ~= nil and st.face.valid then
                st.face.selfStyle.bgcolor = "white"
            end
        end,
    },
    {
        --hearts float up from the card, which sways.
        id = "love",
        text = "Love",
        icon = "phosphor/heart-fill.png",
        build = function(fx, w, h)
            local hearts = {}
            for i = 1, 4 do
                hearts[i] = Sprite(fx, w * 0.15, {image = "phosphor/heart-fill.png", color = "#ff5d8f"})
                hearts[i].selfStyle.scale = 0.01
            end
            return {hearts = hearts}
        end,
        update = function(st, t, w, h)
            local s = w * 0.15
            for i, heart in ipairs(st.hearts) do
                local u = Cycle(t, 1.6, (i - 1) * 0.4)
                if u == nil then
                    heart.selfStyle.scale = 0.01
                else
                    local fx = cond(i % 2 == 0, 0.68, 0.32)
                    heart.x = w * fx - s / 2 + math.sin(u * 6 + i) * w * 0.06
                    heart.y = h * 0.05 - u * h * 0.4
                    heart.selfStyle.scale = math.max(0.01, math.sin(u * math.pi) * 1.15)
                end
            end
            return 0, math.sin(t * 4) * w * 0.012
        end,
    },
    {
        --a single question mark floats up from the card, tilting, again
        --and again.
        id = "confused",
        text = "Confused",
        icon = "phosphor/question-mark-bold.png",
        build = function(fx, w, h)
            local mark = Sprite(fx, w * 0.26, {image = "phosphor/question-mark-bold.png"})
            mark.selfStyle.scale = 0.01
            return {mark = mark}
        end,
        update = function(st, t, w, h)
            local s = w * 0.26
            local period = 1.65
            local u = Cycle(t, period) or 0
            st.mark.x = w * 0.6 - s / 2 + math.sin(u * 5) * w * 0.04
            st.mark.y = -s * 0.6 - u * h * 0.3
            st.mark.selfStyle.rotate = math.sin(t * 3) * 14
            st.mark.selfStyle.scale = math.max(0.01, math.min(Pop(u * period), (1 - u) * 5))
            return math.sin(t * 2.2) * w * 0.012, 0
        end,
    },
    {
        --Zs drift up from the card as it breathes slowly.
        id = "sleepy",
        text = "Sleepy",
        icon = "phosphor/moon-fill.png",
        build = function(fx, w, h)
            local zs = {}
            for i = 1, 3 do
                zs[i] = Sprite(fx, w * 0.2, {text = "Z", color = "white", fontSize = w * 0.16})
                zs[i].selfStyle.scale = 0.01
            end
            return {zs = zs}
        end,
        update = function(st, t, w, h)
            for i, z in ipairs(st.zs) do
                local u = Cycle(t, 2.4, (i - 1) * 0.8)
                if u == nil then
                    z.selfStyle.scale = 0.01
                else
                    z.x = w * (0.66 + 0.22 * u)
                    z.y = -w * 0.1 - u * h * 0.32
                    z.selfStyle.scale = math.max(0.01, math.min(0.5 + u, (1 - u) * 6))
                end
            end
            return 0, math.sin(t * 2) * w * 0.012
        end,
    },
}

local g_emoteById = {}
for _, emote in ipairs(SceneElements.EMOTES) do
    g_emoteById[emote.id] = emote
end

--sceneid|id -> {id, t}: the emote each card is playing.
local g_emotes = {}

--- Plays an emote on a card in a scene, for everyone.
--- @param sceneid string
--- @param id string the element id
--- @param emoteid string an id from SceneElements.EMOTES
function SceneElements.Emote(sceneid, id, emoteid)
    if g_emoteById[emoteid] == nil then
        return
    end
    g_emotes[LiveKey(sceneid, id)] = {id = emoteid, t = dmhub.Time()}
    dmhub.BroadcastRemoteEvent(EMOTE_EVENT, LiveKey(sceneid, id), {
        gameid = dmhub.gameid,
        from = g_clientId,
        sceneid = sceneid,
        id = id,
        emote = emoteid,
    }, true, true)
end

dmhub.RegisterRemoteEvent(EMOTE_EVENT, function(info)
    if mod.unloaded or type(info) ~= "table" or info.gameid ~= dmhub.gameid or info.from == g_clientId then
        return
    end
    if type(info.sceneid) ~= "string" or type(info.id) ~= "string" or g_emoteById[info.emote] == nil then
        return
    end
    g_emotes[LiveKey(info.sceneid, info.id)] = {id = info.emote, t = dmhub.Time()}
end)

--- The emote a card is playing and how many seconds in, or nil.
--- @return nil|SceneEmote, number, number the emote, seconds in, when it started
local function EmoteOf(sceneid, id)
    local key = LiveKey(sceneid, id)
    local e = g_emotes[key]
    if e == nil then
        return nil, 0, 0
    end
    local t = dmhub.Time() - e.t
    if t >= EMOTE_SECONDS then
        g_emotes[key] = nil
        return nil, 0, 0
    end
    return g_emoteById[e.id], t, e.t
end

----------------------------------------------------------------------
--The layer drawn over a scene's picture.

--Every built layer, to find the one under the mouse (DropOnBackground).
local g_layers = setmetatable({}, {__mode = "k"})

--The drag of a card in a scene, or of one of its resize grips:
--{layer, sceneid, id, item, grip, canMove, canRemove, x, y, w, ...}
local g_drag = nil

--Whether a card is being moved by this user's drag: the card dragged, or
--one of the selected cards following it (g_drag.followers).
local function Dragged(item)
    local drag = g_drag
    return drag ~= nil and (drag.item == item or (drag.followers ~= nil and drag.followers[item] ~= nil))
end

--- The creature cards on open scenes, as targets for the tabletop's selection
--- rectangle: {charid, panel} each. backgroundOnly: only a scene that is the
--- table's background; onlyLayer: only that scene's layer.
--- @param backgroundOnly boolean
--- @param onlyLayer nil|Panel
--- @return {charid: string, panel: Panel}[]
function SceneElements.CreatureCardTargets(backgroundOnly, onlyLayer)
    local out = {}
    for layer in pairs(g_layers) do
        if layer.valid and (onlyLayer == nil or layer == onlyLayer) and (not backgroundOnly or layer.data.background) then
            for _, item in pairs(layer.data.items or {}) do
                if item.el.kind == "creature" and item.panel.valid then
                    out[#out+1] = {charid = item.el.charid, panel = item.panel}
                end
            end
        end
    end
    return out
end

--- Takes the cards of these creatures out of every scene open here that this
--- user may take them out of (the Director's Delete on selected cards). The
--- creatures themselves stay.
--- @param charids table<string, boolean>
function SceneElements.RemoveCreatureCards(charids)
    local byScene = {}
    for layer in pairs(g_layers) do
        if layer.valid then
            local sceneid = layer.data.sceneid
            for id, item in pairs(layer.data.items or {}) do
                if item.el.kind == "creature" and charids[item.el.charid] and SceneElements.CanRemoveElement(sceneid, item.el) then
                    byScene[sceneid] = byScene[sceneid] or {}
                    byScene[sceneid][#byScene[sceneid]+1] = id
                end
            end
        end
    end
    for sceneid, ids in pairs(byScene) do
        Change(sceneid, "Remove from scene", function(data)
            for _, id in ipairs(ids) do
                data.elements[id] = nil
            end
        end)
    end
end

--- The mouse as fractions of a layer (top-left origin; outside it is outside 0-1).
--- @param layer Panel
--- @return number, number
local function MouseFraction(layer)
    local p = layer.mousePoint
    return p.x, 1 - p.y
end

local function MouseInside(layer)
    local x, y = MouseFraction(layer)
    return x >= 0 and x <= 1 and y >= 0 and y <= 1
end

--- The stage's height / width.
--- @param layer Panel
--- @return number
local function StageAspect(layer)
    return layer.data.sh / math.max(1, layer.data.sw)
end

--- For debugging over MCP: every live layer's scene, stage size, whether it
--- is the table's background, and where the mouse is on it.
--- @return string
function SceneElements.DescribeLayers()
    local lines = {}
    for layer in pairs(g_layers) do
        if layer.valid then
            local fx, fy = MouseFraction(layer)
            lines[#lines+1] = string.format("%s stage=%dx%d background=%s count=%s mouse=%.3f,%.3f",
                layer.data.sceneid, math.floor(layer.data.sw), math.floor(layer.data.sh),
                tostring(layer.data.background), tostring(layer.data.count), fx, fy)
        end
    end
    return table.concat(lines, "\n")
end

local function BackgroundLayerUnderMouse()
    for layer in pairs(g_layers) do
        if layer.valid and layer.data.background and MouseInside(layer) then
            return layer
        end
    end
    return nil
end

--- A drop on the bare table (the tabletop's drop handlers ask): when the
--- table's background is a scene (maximized under the UI, or the full-screen
--- display under it) what the links name enters it at the mouse instead.
--- @param links any[] SceneLinks (nil entries and anything else are skipped)
--- @return boolean taken
function SceneElements.DropLinksOnBackground(links)
    local layer = BackgroundLayerUnderMouse()
    if layer == nil then
        return false
    end
    local fx, fy = MouseFraction(layer)
    return SceneElements.TakeLinks(layer.data.sceneid, links, fx, fy, StageAspect(layer))
end

--- DropLinksOnBackground for characters (table cards, map tokens) or
--- bestiary monsters.
--- @param charids nil|string[]
--- @param monsterids nil|string[]
--- @return boolean taken
function SceneElements.DropOnBackground(charids, monsterids)
    local links = {}
    for _, charid in ipairs(charids or {}) do
        links[#links+1] = {kind = "character", id = charid}
    end
    for _, monsterid in ipairs(monsterids or {}) do
        links[#links+1] = {kind = "monster", id = monsterid}
    end
    return SceneElements.DropLinksOnBackground(links)
end

----------------------------------------------------------------------
--Playing scene sounds. This computer "has a scene open" while one of its
--layers of that scene thinks (thinking stops while a panel is hidden: a
--minimized window, a scene collapsed for the Director). Every tenth of a
--second the sounds of the open scenes that should be heard (SoundState) are
--started here with asset:Play() -- this computer only -- and any others are
--stopped.

--sceneid -> when one of this computer's layers of it last thought.
local g_viewing = {}
--sceneid|id -> {instance, seq, assetid}: the scene sounds playing here.
local g_sounds = {}
local g_soundsTicking = false

--A scene whose layers have not thought for this long is not open.
local VIEW_SECONDS = 0.4

--A clip's category is the mix group its personal volume slider sets.
local SOUND_MIX_GROUPS = {music = true, ambience = true, effects = true}

local function StopSound(key)
    local s = g_sounds[key]
    g_sounds[key] = nil
    if s ~= nil and s.instance.playing then
        s.instance:Stop()
    end
end

--Matches what plays here to the scenes open here. Returns whether there is
--anything left to watch.
local function DriveSounds()
    local now = dmhub.Time()
    local wanted = {}
    for sceneid, t in pairs(g_viewing) do
        if now - t > VIEW_SECONDS then
            g_viewing[sceneid] = nil
        else
            local elements = Doc(sceneid).data.elements
            if type(elements) == "table" then
                for id, el in pairs(elements) do
                    if type(el) == "table" and el.kind == "audio" then
                        local playing, offset = SoundState(el)
                        if playing then
                            wanted[LiveKey(sceneid, id)] = {el = el, offset = offset}
                        end
                    end
                end
            end
        end
    end
    --switched off, switched on again (a new seq), or no longer open here.
    for key, s in pairs(g_sounds) do
        local want = wanted[key]
        if want == nil or want.el.seq ~= s.seq or want.el.key ~= s.assetid then
            StopSound(key)
        end
    end
    for key, want in pairs(wanted) do
        local asset = SoundAsset(want.el)
        if g_sounds[key] == nil and asset ~= nil then
            local instance = asset:Play() --[[@as nil|SoundEventInstanceLua]]
            if instance ~= nil then
                instance.loop = asset.loop == true
                if SOUND_MIX_GROUPS[asset.category] then
                    instance.mixGroupId = asset.category
                end
                --joining part-way: at the same point as everyone else.
                if want.offset > 0.5 then
                    instance.time = want.offset
                end
                g_sounds[key] = {instance = instance, seq = want.el.seq, assetid = want.el.key}
            end
        end
    end
    return next(g_viewing) ~= nil or next(g_sounds) ~= nil
end

local function TickSounds()
    if mod.unloaded then
        g_soundsTicking = false
        return
    end
    if DriveSounds() then
        dmhub.Schedule(0.1, TickSounds)
    else
        g_soundsTicking = false
    end
end

--A layer of the scene thought: the scene is open here.
local function SceneOpenHere(sceneid)
    g_viewing[sceneid] = dmhub.Time()
    if not g_soundsTicking then
        g_soundsTicking = true
        dmhub.Schedule(0.05, TickSounds)
    end
end

--a reloaded mod must not leave its sounds playing with no one to stop them.
mod.unloadHandlers[#mod.unloadHandlers+1] = function()
    for key in pairs(g_sounds) do
        StopSound(key)
    end
end

local SCENE_STYLES = {
    {
        selectors = {"sceneElementAway"},
        opacity = 0.45,
    },
    {
        selectors = {"sceneElementGhost"},
        opacity = 0.5,
    },
    --(the ring only while shown: a border ignores the hidden chrome's opacity.)
    {
        selectors = {"sceneElementClose"},
        bgcolor = "#1d1915d0",
        borderColor = "#d8d0c2",
        borderWidth = 0,
    },
    {
        selectors = {"sceneElementClose", "shown"},
        borderWidth = 1,
    },
    {
        selectors = {"sceneElementClose", "hover"},
        bgcolor = "#a3322bff",
    },
    {
        selectors = {"sceneElementSpeak", "hover"},
        bgcolor = "#3d6e8cff",
    },
    --a picture's frame, as a journal picture's on the table.
    {
        selectors = {"sceneElementMedia"},
        bgcolor = "#1d1915f2",
        borderColor = "#d9d1c440",
        borderWidth = 1,
        cornerRadius = 6,
    },
    --a sound's tile: dim while off, lit gold while it plays.
    {
        selectors = {"sceneSound"},
        bgcolor = "#1d1915e6",
        borderColor = "#d9d1c440",
        borderWidth = 1,
        cornerRadius = 8,
    },
    {
        selectors = {"sceneSound", "sceneSoundOn"},
        bgcolor = "#2e2618f2",
        borderColor = "#d9b56a",
        borderWidth = 2,
        transitionTime = 0.15,
    },
    {
        selectors = {"sceneSoundIcon"},
        bgcolor = "#a39a8c",
    },
    {
        selectors = {"sceneSoundIcon", "sceneSoundOn"},
        bgcolor = "#f0d48a",
    },
    {
        selectors = {"sceneSoundName"},
        color = "#efe8dc",
    },
    {
        selectors = {"sceneSoundStatus"},
        color = "#a39a8c",
    },
    {
        selectors = {"sceneSoundStatus", "sceneSoundOn"},
        color = "#f0d48a",
    },
}

--The bubble's paper and ink.
local BUBBLE_COLOR = "#f4efe4"
local BUBBLE_INK = "#1d1915"

local function Styles()
    local styles = Tabletop.CardStyles()
    for _, rule in ipairs(SCENE_STYLES) do
        styles[#styles+1] = rule
    end
    return styles
end

--Draws an item at (x, y, w): fractions of the stage.
local function Position(layer, item, x, y, w)
    item.cur = {x = x, y = y, w = w}
    local sw, sh = layer.data.sw, layer.data.sh
    local W = w * sw
    local H = W * item.nativeH / item.nativeW
    local panel = item.panel
    panel.x = x * sw
    panel.y = y * sh
    panel.selfStyle.width = W
    panel.selfStyle.height = H
    item.scaler.selfStyle.scale = W / item.nativeW
end

--The height of an item as a fraction of the stage, at width w.
local function HeightFraction(layer, item, w)
    return w * (item.nativeH / item.nativeW) / StageAspect(layer)
end

--- @param sceneid string
--- @param options nil|{onCount: nil|fun(count: integer)}
--- @return Panel
function SceneElements.CreateLayer(sceneid, options)
    options = options or {}
    --id -> {id, el, key, panel, scaler, nativeW, nativeH, cur, grips, close,
    --speak, editing, speech}
    local m_items = {}
    local m_order = nil
    local m_ghost = nil
    local m_refresh = 0
    local Restage
    local layer

    --Over every card: the emotes' effects, then the speech bubbles and the
    --box a line is typed into.
    local m_fxLayer = gui.Panel{
        halign = "left",
        valign = "top",
        width = 1,
        height = 1,
        flow = "none",
    }
    local m_speechLayer = gui.Panel{
        halign = "left",
        valign = "top",
        width = 1,
        height = 1,
        flow = "none",
    }

    local function DestroyGhost()
        if m_ghost ~= nil and m_ghost.valid then
            m_ghost:DestroySelf()
        end
        m_ghost = nil
    end

    --What a drop here would make, following the mouse while something is
    --dragged over the scene. link has passed CanTake (DroppableItem).
    local function ShowGhost(link)
        DestroyGhost()
        if link == nil then
            return
        end
        local face, cw, ch, width
        if link.kind == "monster" then
            face = Tabletop.BestiaryCardFace(assets.monsters[link.id].info)
            cw, ch = Tabletop.CardSize()
            width = DEFAULT_WIDTH
        else
            local el = ElementOfLink(link)
            if el == nil then
                return
            end
            local kind = SceneElements.kinds[el.kind]
            face, cw, ch = kind.build(el)
            width = kind.defaultWidth or DEFAULT_WIDTH
        end
        local W = width * layer.data.sw
        local H = W * ch / cw
        --born under the mouse: the think that moves it runs a frame later,
        --and until then it would sit at the scene's top-left.
        local fx, fy = MouseFraction(layer)
        m_ghost = gui.Panel{
            styles = Styles(),
            classes = {"sceneElementGhost"},
            halign = "left",
            valign = "top",
            x = fx * layer.data.sw - W / 2,
            y = fy * layer.data.sh - H / 2,
            width = W,
            height = H,
            flow = "none",
            gui.Panel{
                halign = "center",
                valign = "center",
                width = cw,
                height = ch,
                scale = W / cw,
                face,
            },
        }
        layer:AddChild(m_ghost)
        m_ghost:FireEventTree("refreshCard")
        m_ghost:SetClassTree("sceneElementGhost", true)
        m_ghost:MakeNonInteractiveRecursive()
    end

    local function MoveGhost()
        if m_ghost == nil or not m_ghost.valid then
            return
        end
        local fx, fy = MouseFraction(layer)
        m_ghost.x = fx * layer.data.sw - m_ghost.selfStyle.width / 2
        m_ghost.y = fy * layer.data.sh - m_ghost.selfStyle.height / 2
        m_ghost:SetAsLastSibling()
    end

    --The first link a drag offers that this user may put into this scene.
    --- @return nil|SceneLink
    local function DroppableItem(items)
        for _, item in pairs(items or {}) do
            if CanTake(sceneid, item) then
                return item
            end
        end
        return nil
    end

    local function TakeDrop(items)
        DestroyGhost()
        local fx, fy = MouseFraction(layer)
        SceneElements.TakeLinks(sceneid, items or {}, fx, fy, StageAspect(layer))
    end

    local function CharacterItems(charids)
        local items = {}
        for _, charid in ipairs(charids or {}) do
            items[#items+1] = ChatItemLinks.CharacterItem(charid)
        end
        return items
    end

    ------------------------------------------------------------------
    --Dragging a card: moving it within its scene, or out of it.

    local function DragItemLink(item)
        local kind = SceneElements.kinds[item.el.kind]
        local link = kind.item(item.el)
        if link == nil then
            return {}
        end
        local copy = {}
        for k, v in pairs(link) do
            copy[k] = v
        end
        --another scene that takes it moves it there (TakeDrop).
        copy.fromScene = sceneid
        copy.fromElement = item.id
        return {copy}
    end

    --The preview of what a drop on the table would make goes.
    local function EndPreview(item, element)
        local kind = SceneElements.kinds[item.el.kind]
        if g_drag ~= nil and kind ~= nil and kind.tableDragEnded ~= nil then
            kind.tableDragEnded(item.el, element, g_drag)
        end
    end

    --Whether a drag released now lands back in this scene.
    local function OverHome()
        if layer.data.background then
            return MouseInside(layer) and dmhub.tokenDropTargetUnderMouse == nil
        end
        return dmhub.tokenDropTargetUnderMouse == layer
    end

    local function BeginDrag(item)
        local fx, fy = MouseFraction(layer)
        local cur = item.cur or {x = item.el.x, y = item.el.y, w = item.el.w}
        g_drag = {
            layer = layer,
            sceneid = sceneid,
            id = item.id,
            item = item,
            canMove = SceneElements.CanChange(sceneid, item.el),
            canRemove = SceneElements.CanRemoveElement(sceneid, item.el),
            grabX = fx - cur.x,
            grabY = fy - cur.y,
            x = cur.x,
            y = cur.y,
            w = cur.w,
            lastSend = 0,
            moved = false,
        }
        --the other selected creature cards in this scene that this user may
        --move follow it, keeping their places relative to it.
        if item.el.kind == "creature" and g_drag.canMove then
            local selected = Tabletop.SelectedCharids()
            if selected[item.el.charid] then
                for _, other in pairs(m_items) do
                    if other ~= item and other.el.kind == "creature" and selected[other.el.charid]
                            and other.panel.valid and SceneElements.CanChange(sceneid, other.el) then
                        local ocur = other.cur or {x = other.el.x, y = other.el.y, w = other.el.w}
                        g_drag.followers = g_drag.followers or {}
                        g_drag.followers[other] = {x0 = ocur.x, y0 = ocur.y, w = ocur.w, x = ocur.x, y = ocur.y}
                    end
                end
            end
        end
        g_drag.x0 = cur.x
        g_drag.y0 = cur.y
    end

    --Moves the cards following a drag by its offset from where it started
    --(home again while the drag is away from the scene).
    local function MoveFollowers(drag, home)
        if drag.followers == nil then
            return
        end
        local dx, dy = 0, 0
        if home then
            dx, dy = drag.x - drag.x0, drag.y - drag.y0
        end
        for other, f in pairs(drag.followers) do
            if other.panel.valid then
                f.x = Clamp(f.x0 + dx, 0, 1 - f.w)
                f.y = Clamp(f.y0 + dy, 0, 1 - HeightFraction(layer, other, f.w))
                Position(layer, other, f.x, f.y, f.w)
            end
        end
    end

    local function Stream(final)
        local drag = g_drag
        if drag == nil then
            return
        end
        local now = dmhub.Time()
        if final or now - drag.lastSend >= SEND_INTERVAL then
            drag.lastSend = now
            SendMove(sceneid, drag.id, drag.x, drag.y, drag.w, final)
            for other, f in pairs(drag.followers or {}) do
                SendMove(sceneid, other.id, f.x, f.y, f.w, final)
            end
        end
    end

    local function Dragging(item, element)
        local drag = g_drag
        if drag == nil or drag.item ~= item then
            return
        end
        local kind = SceneElements.kinds[item.el.kind]
        if kind.sceneOnly then
            --(a sound): only another scene takes it, never the chat or a journal.
            ChatItemLinks.Dragging(function() return {} end, {
                source = element,
                targetClass = SceneElements.LAYER_CLASS,
                dropItems = function() return DragItemLink(item) end,
            })
        else
            ChatItemLinks.Dragging(function()
                return DragItemLink(item)
            end, {source = element})
        end

        local home = OverHome()
        if home and drag.canMove then
            local fx, fy = MouseFraction(layer)
            drag.x = Clamp(fx - drag.grabX, 0, 1 - drag.w)
            drag.y = Clamp(fy - drag.grabY, 0, 1 - HeightFraction(layer, item, drag.w))
            drag.moved = true
            Position(layer, item, drag.x, drag.y, drag.w)
            MoveFollowers(drag, true)
            Stream(false)
        end
        if not home then
            MoveFollowers(drag, false)
        end
        local away = not home
        if element:HasClass("sceneElementAway") ~= away then
            element:SetClassTree("sceneElementAway", away)
        end

        --over the bare table it would leave the scene for a card, picture or
        --sound there; the kind shows what that would be.
        if kind.tableDragging ~= nil and drag.canRemove and Tabletop.IsActive() then
            local toTable = away and dmhub.panelDropSurface == "table"
            kind.tableDragging(item.el, element, toTable, drag)
        end
    end

    local function Drop(item, element)
        local drag = g_drag
        if drag == nil or drag.item ~= item then
            return
        end
        --the chat takes a link, a journal a tag; another scene takes the
        --element (TakeDrop).
        local taken = ChatItemLinks.Dropped()
        local home = OverHome()
        local toTable = not home and drag.canRemove and Tabletop.IsActive() and dmhub.panelDropSurface == "table"
        EndPreview(item, element)
        g_drag = nil
        element:SetClassTree("sceneElementAway", false)
        if taken then
            return
        end
        if home and drag.canMove and drag.moved then
            SceneElements.Place(sceneid, item.id, drag.x, drag.y, drag.w)
            item.pending = {x = drag.x, y = drag.y, w = drag.w, t = dmhub.Time()}
            SendMove(sceneid, item.id, drag.x, drag.y, drag.w, true)
            for other, f in pairs(drag.followers or {}) do
                SceneElements.Place(sceneid, other.id, f.x, f.y, f.w)
                other.pending = {x = f.x, y = f.y, w = f.w, t = dmhub.Time()}
                SendMove(sceneid, other.id, f.x, f.y, f.w, true)
            end
            return
        end
        --(any other drop: the followers ease back home in Animate.)
        local kind = SceneElements.kinds[item.el.kind]
        if toTable and kind.toTable ~= nil then
            local el = item.el
            SceneElements.Remove(sceneid, item.id)
            kind.toTable(el, dmhub.mouseScreenPosition)
        end
    end

    ------------------------------------------------------------------
    --Resizing: a grip on each corner keeps the opposite corner in place.

    local GRIP = 14

    local function Grip(item, hx, hy)
        local cursor = cond(hx == hy, "diagonal-expand", "diagonal-expand-mirror")
        local found = false
        for _, id in ipairs(dmhub.cursorIds or {}) do
            if id == cursor then
                found = true
            end
        end
        if not found then
            cursor = "diagonal-expand"
        end
        return gui.Panel{
            floating = true,
            width = GRIP,
            height = GRIP,
            halign = cond(hx < 0, "left", "right"),
            valign = cond(hy < 0, "top", "bottom"),
            x = cond(hx < 0, -GRIP / 2, GRIP / 2),
            y = cond(hy < 0, -GRIP / 2, GRIP / 2),
            bgimage = true,
            bgcolor = "clear",
            hoverCursor = cursor,
            swallowPress = true,
            draggable = true,
            dragMove = false,
            beginDrag = function(element)
                local cur = item.cur or {x = item.el.x, y = item.el.y, w = item.el.w}
                local h = HeightFraction(layer, item, cur.w)
                g_drag = {
                    layer = layer,
                    sceneid = sceneid,
                    id = item.id,
                    item = item,
                    grip = true,
                    --the corner that stays put.
                    ax = cond(hx < 0, cur.x + cur.w, cur.x),
                    ay = cond(hy < 0, cur.y + h, cur.y),
                    x = cur.x,
                    y = cur.y,
                    w = cur.w,
                    lastSend = 0,
                    moved = false,
                }
            end,
            dragging = function(element)
                local drag = g_drag
                if drag == nil or drag.item ~= item or not drag.grip then
                    return
                end
                local fx, fy = MouseFraction(layer)
                local sw, sh = layer.data.sw, layer.data.sh
                local a = item.nativeH / item.nativeW
                --in stage pixels, projected onto the card's diagonal.
                local wantW = math.abs(fx - drag.ax) * sw
                local wantH = math.abs(fy - drag.ay) * sh
                local W = (wantW + wantH * a) / (1 + a * a)
                local w = Clamp(W / sw, MIN_WIDTH, SceneElements.kinds[item.el.kind].maxWidth or MAX_WIDTH)
                --and it stays on the picture.
                local roomX = cond(hx < 0, drag.ax, 1 - drag.ax)
                local roomY = cond(hy < 0, drag.ay, 1 - drag.ay)
                w = math.min(w, roomX, roomY / math.max(0.0001, HeightFraction(layer, item, 1)))
                local h = HeightFraction(layer, item, w)
                drag.w = w
                drag.x = cond(hx < 0, drag.ax - w, drag.ax)
                drag.y = cond(hy < 0, drag.ay - h, drag.ay)
                drag.moved = true
                Position(layer, item, drag.x, drag.y, drag.w)
                Stream(false)
            end,
            drag = function(element)
                local drag = g_drag
                if drag == nil or drag.item ~= item then
                    return
                end
                g_drag = nil
                if drag.moved then
                    SceneElements.Place(sceneid, item.id, drag.x, drag.y, drag.w)
                    item.pending = {x = drag.x, y = drag.y, w = drag.w, t = dmhub.Time()}
                    SendMove(sceneid, item.id, drag.x, drag.y, drag.w, true)
                end
            end,
        }
    end

    ------------------------------------------------------------------
    --Speech: the bubble above a card, and the box a line is typed into
    --(both in m_speechLayer, so no card covers them).

    --The text size follows the stage, so a bubble reads the same in a small
    --window and full screen.
    local function SpeechFontSize()
        return Clamp(layer.data.sh * 0.028, 12, 26)
    end

    --Each bubble is centred along the bottom of a slot this big.
    local SLOT_W = 900
    local SLOT_H = 600

    local function DestroySpeech(item)
        if item.speech ~= nil and item.speech.valid then
            item.speech:DestroySelf()
        end
        item.speech = nil
        item.bubble = nil
        item.bubbleScale = nil
    end

    local UpdateSpeech

    local function CloseEditor(item)
        item.editing = false
        DestroySpeech(item)
        UpdateSpeech(item)
    end

    local function BuildSpeech(item, text, editing, fs)
        local content
        if editing then
            local submitted = false
            content = gui.Input{
                width = fs * 16,
                height = fs * 1.5,
                fontSize = fs,
                fontFace = "Berling",
                color = BUBBLE_INK,
                bgimage = "panels/square.png",
                bgcolor = "clear",
                borderWidth = 0,
                placeholderText = "Say something...",
                characterLimit = SPEECH_LIMIT,
                hasInputFocus = true,
                submit = function(element)
                    submitted = true
                    local line = element.text
                    CloseEditor(item)
                    SceneElements.Say(sceneid, item.id, line)
                end,
                --focus left without Enter (a click elsewhere, Escape): say nothing.
                change = function(element)
                    dmhub.Schedule(0.1, function()
                        if mod.unloaded or submitted or not element.valid or element.hasInputFocus then
                            return
                        end
                        if item.editing then
                            CloseEditor(item)
                        end
                    end)
                end,
            }
        else
            content = gui.Label{
                text = text,
                fontSize = fs,
                fontFace = "Berling",
                color = BUBBLE_INK,
                width = "auto",
                height = "auto",
                maxWidth = fs * 16,
                halign = "center",
                valign = "center",
                textAlignment = "center",
                textWrap = true,
                interactable = false,
            }
        end

        local tail = fs * 1.2
        item.bubble = gui.Panel{
            halign = "center",
            valign = "bottom",
            width = "auto",
            height = "auto",
            flow = "vertical",
            gui.Panel{
                halign = "center",
                width = "auto",
                height = "auto",
                hpad = fs * 0.6,
                vpad = fs * 0.35,
                borderBox = true,
                bgimage = "panels/square.png",
                bgcolor = BUBBLE_COLOR,
                cornerRadius = fs * 0.6,
                borderColor = BUBBLE_INK,
                borderWidth = 1.5,
                interactable = editing,
                content,
            },
            --the caret's triangle fills 34%-72% of its image's height, so it
            --tucks up over the bubble's bottom edge.
            gui.Panel{
                halign = "center",
                width = tail,
                height = tail,
                y = -tail * 0.36,
                bgimage = "phosphor/caret-down-fill.png",
                bgcolor = BUBBLE_COLOR,
                interactable = false,
            },
        }
        item.speech = gui.Panel{
            halign = "left",
            valign = "top",
            width = SLOT_W,
            height = SLOT_H,
            flow = "none",
            data = {text = text, editing = editing, fs = fs, tail = tail},
            item.bubble,
        }
        m_speechLayer:AddChild(item.speech)
    end

    --Shows (or takes down) a card's bubble and keeps it over the card.
    UpdateSpeech = function(item)
        local text, alpha = SpeechOf(sceneid, item.id)
        local editing = item.editing == true
        if not editing and text == nil then
            DestroySpeech(item)
            return
        end
        if editing then
            alpha = 1
        end
        local fs = SpeechFontSize()
        local s = item.speech
        local stale = s == nil or not s.valid or s.data.editing ~= editing
        --(an open editor is not rebuilt for a new size: it would lose the typing.)
        if not stale and not editing then
            stale = s.data.text ~= text or math.abs(s.data.fs - fs) > 0.5
        end
        if stale then
            DestroySpeech(item)
            BuildSpeech(item, text, editing, fs)
            s = item.speech
        end
        if s == nil then
            return
        end
        local cur = item.cur or {x = item.el.x, y = item.el.y, w = item.el.w}
        local sw, sh = layer.data.sw, layer.data.sh
        --the tail's tip on the card's top edge; a card at the top of the
        --picture has the bubble overlap it rather than leave the picture.
        local bottom = math.max(cur.y * sh + s.data.tail * 0.64, s.data.fs * 3)
        s.x = (cur.x + cur.w / 2) * sw - SLOT_W / 2
        s.y = bottom - SLOT_H
        --it shrinks away as it ends (a parent's opacity does not fade children).
        --(the scale is remembered here: reading selfStyle.scale back raises.)
        local scale = 0.6 + 0.4 * alpha
        if item.bubble ~= nil and item.bubble.valid and item.bubbleScale ~= scale then
            item.bubbleScale = scale
            item.bubble.selfStyle.scale = scale
        end
    end

    ------------------------------------------------------------------
    --Emotes: the effects sit in m_fxLayer over the card, at the card's
    --native size scaled like its face; the face itself is jolted by moving
    --its scaler.

    local function DestroyEmote(item)
        if item.fxEmote ~= nil and item.fxEmote.finish ~= nil and item.fxState ~= nil then
            item.fxEmote.finish(item.fxState)
        end
        if item.fx ~= nil and item.fx.valid then
            item.fx:DestroySelf()
        end
        item.fx = nil
        item.fxInner = nil
        item.fxState = nil
        item.fxStart = nil
        item.fxEmote = nil
        if item.shaken then
            item.shaken = false
            if item.scaler.valid then
                item.scaler.x = 0
                item.scaler.y = 0
            end
        end
    end

    local function UpdateEmote(item)
        local emote, t, start = EmoteOf(sceneid, item.id)
        if emote == nil then
            DestroyEmote(item)
            return
        end
        local w, h = item.nativeW, item.nativeH
        if item.fx == nil or not item.fx.valid or item.fxStart ~= start then
            DestroyEmote(item)
            item.fxInner = gui.Panel{
                halign = "center",
                valign = "center",
                width = w,
                height = h,
                flow = "none",
                interactable = false,
            }
            item.fx = gui.Panel{
                halign = "left",
                valign = "top",
                width = 1,
                height = 1,
                flow = "none",
                interactable = false,
                item.fxInner,
            }
            m_fxLayer:AddChild(item.fx)
            item.fxState = emote.build(item.fxInner, w, h, {face = item.face, el = item.el})
            item.fxStart = start
            item.fxEmote = emote
        end
        local cur = item.cur or {x = item.el.x, y = item.el.y, w = item.el.w}
        local W = cur.w * layer.data.sw
        local k = W / w
        item.fx.x = cur.x * layer.data.sw
        item.fx.y = cur.y * layer.data.sh
        item.fx.selfStyle.width = W
        item.fx.selfStyle.height = W * h / w
        item.fxInner.selfStyle.scale = k
        local dx, dy = emote.update(item.fxState, t, w, h)
        item.scaler.x = dx * k
        item.scaler.y = dy * k
        item.fxInner.x = dx * k
        item.fxInner.y = dy * k
        item.shaken = true
    end

    local function ShowEmotes(item, element)
        local entries = {}
        for _, emote in ipairs(SceneElements.EMOTES) do
            entries[#entries+1] = {
                text = emote.text,
                icon = emote.icon,
                click = function()
                    element.popup = nil
                    SceneElements.Emote(sceneid, item.id, emote.id)
                end,
            }
        end
        element.tooltip = nil
        element.popup = gui.ContextMenu{entries = entries}
    end

    ------------------------------------------------------------------
    --Building the cards.

    local function ShowChrome(item, on)
        if item.close ~= nil and item.close.valid then
            item.close:SetClassTree("shown", on)
        end
        if item.speak ~= nil and item.speak.valid then
            item.speak:SetClassTree("shown", on)
        end
        if item.emote ~= nil and item.emote.valid then
            item.emote:SetClassTree("shown", on)
        end
        Tabletop.ShowCardSheetButton(item.sheet, on)
    end

    local function ShowMenu(item, element)
        local entries = {}
        local kind = SceneElements.kinds[item.el.kind]
        if SceneElements.CanRemoveElement(sceneid, item.el) then
            if Tabletop.IsActive() and kind.toTable ~= nil then
                entries[#entries+1] = {
                    text = "Move to the Table",
                    click = function()
                        element.popup = nil
                        local el = item.el
                        SceneElements.Remove(sceneid, item.id)
                        kind.toTable(el, nil)
                    end,
                }
            end
            entries[#entries+1] = {
                text = "Remove from Scene",
                click = function()
                    element.popup = nil
                    SceneElements.Remove(sceneid, item.id)
                end,
            }
        end
        if #entries > 0 then
            element.tooltip = nil
            element.popup = gui.ContextMenu{entries = entries}
        end
    end

    --Shows the grips and the close button only to those who may use them.
    local function UpdatePermissions(item)
        local canChange = SceneElements.CanChange(sceneid, item.el)
        for _, grip in ipairs(item.grips) do
            if grip:HasClass("collapsed") == canChange then
                grip:SetClass("collapsed", not canChange)
            end
        end
        local canRemove = SceneElements.CanRemoveElement(sceneid, item.el)
        if item.close:HasClass("collapsed") == canRemove then
            item.close:SetClass("collapsed", not canRemove)
        end
        local canSpeak = SceneElements.CanSpeak(item.el)
        if item.speak:HasClass("collapsed") == canSpeak then
            item.speak:SetClass("collapsed", not canSpeak)
            item.emote:SetClass("collapsed", not canSpeak)
        end
        if not canSpeak and item.editing then
            CloseEditor(item)
        end
    end

    local function BuildItem(id, el)
        local kind = SceneElements.kinds[el.kind]
        local face, nativeW, nativeH = kind.build(el)
        local item = {id = id, el = el, key = kind.key(el), face = face, nativeW = nativeW, nativeH = nativeH}

        item.scaler = gui.Panel{
            halign = "center",
            valign = "center",
            width = nativeW,
            height = nativeH,
            scale = 1,
            face,
        }

        item.close = gui.Panel{
            classes = {"sceneElementClose", "tabletopCardChrome"},
            floating = true,
            halign = "right",
            valign = "top",
            x = 8,
            y = -8,
            width = 20,
            height = 20,
            cornerRadius = 10,
            bgimage = "panels/square.png",
            --the press reaches the card, so hovering here keeps it hovered.
            swallowPress = false,
            hover = gui.Tooltip("Remove from the scene"),
            click = function(element)
                SceneElements.Remove(sceneid, id)
            end,
            gui.Panel{
                classes = {"tabletopCardChrome"},
                width = 10,
                height = 10,
                halign = "center",
                valign = "center",
                bgimage = "window-chrome/chrome-close.png",
                bgcolor = "white",
                interactable = false,
            },
        }

        --opens (or closes) the box above the card for a line it says.
        item.speak = gui.Panel{
            classes = {"sceneElementClose", "sceneElementSpeak", "tabletopCardChrome"},
            floating = true,
            --inset from the corner, clear of the top-left resize grip.
            halign = "left",
            valign = "top",
            x = 8,
            y = 8,
            width = 22,
            height = 22,
            cornerRadius = 11,
            bgimage = "panels/square.png",
            swallowPress = false,
            hover = gui.Tooltip("Say something"),
            click = function(element)
                item.editing = not item.editing
                DestroySpeech(item)
                UpdateSpeech(item)
            end,
            gui.Panel{
                classes = {"tabletopCardChrome"},
                width = 14,
                height = 14,
                halign = "center",
                valign = "center",
                bgimage = "phosphor/chat-circle-dots-fill.png",
                bgcolor = "white",
                interactable = false,
            },
        }

        --below it: the menu of emotes the card can play.
        item.emote = gui.Panel{
            classes = {"sceneElementClose", "sceneElementSpeak", "tabletopCardChrome"},
            floating = true,
            halign = "left",
            valign = "top",
            x = 8,
            y = 36,
            width = 22,
            height = 22,
            cornerRadius = 11,
            bgimage = "panels/square.png",
            swallowPress = false,
            hover = gui.Tooltip("Emote"),
            click = function(element)
                ShowEmotes(item, element)
            end,
            gui.Panel{
                classes = {"tabletopCardChrome"},
                width = 14,
                height = 14,
                halign = "center",
                valign = "center",
                bgimage = "phosphor/smiley-fill.png",
                bgcolor = "white",
                interactable = false,
            },
        }

        item.grips = {
            Grip(item, -1, -1),
            Grip(item, 1, -1),
            Grip(item, -1, 1),
            Grip(item, 1, 1),
        }

        local children = {item.scaler}
        --a creature card: the ring it wears while selected, and the button
        --that opens its sheet (under the close button's corner).
        if el.kind == "creature" then
            item.ring = Tabletop.CardSelectRing(8)
            Tabletop.ShowCardSelected(item.ring, Tabletop.SelectedCharids()[el.charid] == true)
            item.sheet = Tabletop.CardSheetButton(el.charid, {x = -8, y = 20})
            children[#children+1] = item.ring
            children[#children+1] = item.sheet
        end
        children[#children+1] = item.close
        children[#children+1] = item.speak
        children[#children+1] = item.emote
        for _, grip in ipairs(item.grips) do
            children[#children+1] = grip
        end

        item.panel = gui.Panel{
            styles = Styles(),
            classes = {"tabletopCard", "sceneElement"},
            halign = "left",
            valign = "top",
            width = 10,
            height = 10,
            cornerRadius = 8,
            flow = "none",
            draggable = true,
            --the drag moves the card itself (Dragging), within the scene.
            dragMove = false,
            swallowPress = true,
            raiseOnPress = true,
            data = {charid = el.charid},
            hover = function(element)
                ShowChrome(item, true)
                if kind.tooltip ~= nil then
                    gui.Tooltip(kind.tooltip(item.el))(element)
                end
            end,
            --a picture opens; a sound switches on or off (a card's face
            --takes its own clicks).
            click = function(element)
                if kind.click ~= nil then
                    kind.click(item.el, sceneid, id)
                end
            end,
            dehover = function(element)
                ShowChrome(item, false)
            end,
            rightClick = function(element)
                ShowMenu(item, element)
            end,
            beginDrag = function(element)
                BeginDrag(item)
            end,
            dragging = function(element)
                Dragging(item, element)
            end,
            drag = function(element)
                Drop(item, element)
            end,
            create = function(element)
                element:FireEventTree("refreshCard")
            end,
            children = children,
        }
        UpdatePermissions(item)
        layer:AddChild(item.panel)
        return item
    end

    local function Sync()
        --only what this user sees (the players never see sounds), which is
        --also what counts towards letterboxing the picture.
        local elements = {}
        for id, el in pairs(SceneElements.Elements(sceneid)) do
            if SceneElements.Visible(el) then
                elements[id] = el
            end
        end
        for id, item in pairs(m_items) do
            local el = elements[id]
            local kind = el ~= nil and SceneElements.kinds[el.kind] or nil
            if el == nil or kind == nil or kind.key(el) ~= item.key or not item.panel.valid then
                if item.panel.valid then
                    item.panel:DestroySelf()
                end
                DestroySpeech(item)
                DestroyEmote(item)
                m_items[id] = nil
            end
        end
        local count = 0
        local order = {}
        for id, el in pairs(elements) do
            count = count + 1
            local item = m_items[id]
            if item == nil then
                item = BuildItem(id, el)
                m_items[id] = item
            end
            --a card being dragged here keeps the drag's spot.
            if not Dragged(item) then
                item.el = el
            end
            --(a sound's tile lights while it plays.)
            item.panel:FireEventTree("refreshElement", el)
            UpdatePermissions(item)
            order[#order+1] = item
        end
        table.sort(order, function(a, b)
            local za, zb = tonumber(a.el.z) or 0, tonumber(b.el.z) or 0
            if za ~= zb then
                return za < zb
            end
            return a.id < b.id
        end)
        local ids = {}
        for i, item in ipairs(order) do
            ids[i] = item.id
        end
        local signature = table.concat(ids, ",")
        if signature ~= m_order then
            m_order = signature
            for _, item in ipairs(order) do
                item.panel:SetAsLastSibling()
            end
            m_fxLayer:SetAsLastSibling()
            m_speechLayer:SetAsLastSibling()
        end
        local creatures = false
        for _, item in pairs(m_items) do
            if item.el.kind == "creature" then
                creatures = true
                break
            end
        end
        if layer.draggable ~= creatures then
            layer.draggable = creatures
        end
        if count ~= layer.data.count then
            layer.data.count = count
            if options.onCount ~= nil then
                options.onCount(count)
            end
        end
    end

    --Redraws every card at its current place on a resized stage.
    Restage = function()
        for _, item in pairs(m_items) do
            if item.panel.valid and item.cur ~= nil then
                Position(layer, item, item.cur.x, item.cur.y, item.cur.w)
            end
        end
    end

    --Eases every card towards where it should be (a remote drag, or the
    --document); a card this user is dragging is where the drag has it.
    local function Animate()
        for id, item in pairs(m_items) do
            if item.panel.valid and not Dragged(item) then
                local tx, ty, tw = TargetOf(sceneid, id, item.el)
                --this user's own drop, until the document has it.
                local pending = item.pending
                if pending ~= nil then
                    local landed = math.abs(item.el.x - pending.x) < 1e-4 and math.abs(item.el.y - pending.y) < 1e-4 and math.abs(item.el.w - pending.w) < 1e-4
                    if landed or dmhub.Time() - pending.t > FINAL_SECONDS then
                        item.pending = nil
                    else
                        tx, ty, tw = pending.x, pending.y, pending.w
                    end
                end
                local cur = item.cur
                if cur == nil then
                    Position(layer, item, tx, ty, tw)
                else
                    local dx, dy, dw = tx - cur.x, ty - cur.y, tw - cur.w
                    if math.abs(dx) > 1e-4 or math.abs(dy) > 1e-4 or math.abs(dw) > 1e-4 then
                        Position(layer, item, cur.x + dx * 0.45, cur.y + dy * 0.45, cur.w + dw * 0.45)
                    elseif dx ~= 0 or dy ~= 0 or dw ~= 0 then
                        Position(layer, item, tx, ty, tw)
                    end
                end
            end
        end
        MoveGhost()
        --this scene is open here, so its sounds play here.
        SceneOpenHere(sceneid)
        --the cards' portraits, stamina and conditions repaint twice a second;
        --Sync catches what no document change announces (a clip that has
        --finished, a DJ granted or revoked, an asset that arrived).
        local now = dmhub.Time()
        if now - m_refresh > 0.5 then
            m_refresh = now
            Sync()
            for _, item in pairs(m_items) do
                if item.panel.valid then
                    item.panel:FireEventTree("refreshCard")
                end
            end
        end
        --the rings follow the selection (a card clicked, a token picked on the map).
        local seq = dmhub.selectedTokensSeq
        if seq ~= layer.data.selSeq then
            layer.data.selSeq = seq
            local selected = Tabletop.SelectedCharids()
            for _, item in pairs(m_items) do
                if item.ring ~= nil then
                    Tabletop.ShowCardSelected(item.ring, selected[item.el.charid] == true)
                end
            end
        end
        --after the repaint, which resets a portrait's colour that Rage tints.
        for _, item in pairs(m_items) do
            if item.panel.valid then
                UpdateEmote(item)
                UpdateSpeech(item)
            end
        end
    end

    layer = gui.Panel{
        classes = {SceneElements.LAYER_CLASS, ChatItemLinks.ITEM_DROP_TARGET_CLASS},
        halign = "center",
        valign = "center",
        width = 1,
        height = 1,
        flow = "none",
        --drop targets are found by what is under the mouse, so the layer
        --needs a (clear) background to count over the picture.
        bgimage = "panels/square.png",
        bgcolor = "clear",
        tokenDropTarget = true,
        data = {sceneid = sceneid, sw = 1, sh = 1, background = false, count = 0, items = m_items, selSeq = nil},

        --with creature cards in it, a click on an empty part of the scene
        --clears the selection and a drag there draws the selection rectangle
        --over its cards (Sync switches draggable). Without any, a drag on the
        --picture moves its window as before.
        dragMove = false,
        click = function(element)
            local mods = dmhub.modKeys
            if element.draggable and not (mods.shift or mods.ctrl) then
                Tabletop.ClearCardSelection()
            end
        end,
        beginDrag = function(element)
            Tabletop.BeginCardMarquee(function()
                return SceneElements.CreatureCardTargets(false, layer)
            end)
        end,
        dragging = function(element)
            Tabletop.DragCardMarquee()
        end,
        drag = function(element)
            Tabletop.EndCardMarquee()
        end,
        monitorGame = SceneElements.DocPath(sceneid),
        refreshGame = function(element)
            Sync()
        end,
        create = function(element)
            Sync()
        end,
        destroy = function(element)
            DestroyGhost()
        end,

        --the picture's rectangle in the view (FullscreenDisplay.CreateSceneView).
        setStage = function(element, w, h)
            if math.abs(w - element.data.sw) < 0.5 and math.abs(h - element.data.sh) < 0.5 then
                return
            end
            element.data.sw = math.max(1, w)
            element.data.sh = math.max(1, h)
            element.selfStyle.width = element.data.sw
            element.selfStyle.height = element.data.sh
            m_speechLayer.selfStyle.width = element.data.sw
            m_speechLayer.selfStyle.height = element.data.sh
            m_fxLayer.selfStyle.width = element.data.sw
            m_fxLayer.selfStyle.height = element.data.sh
            --every card moves with the stage now, not on the next think, so a
            --resizing window carries its cards smoothly.
            Restage()
        end,

        --the table's background (a maximized scene under the UI): the mouse
        --goes through it to the table, so the tabletop's drop handlers pass
        --drops on it here (DropOnBackground). Its cards still take the mouse.
        setBackground = function(element, background)
            background = background == true
            if element.data.background ~= background then
                element.data.background = background
                element.interactable = not background
            end
        end,

        thinkTime = 0.03,
        think = function(element)
            Animate()
        end,

        --panel drags (rows, table cards and items, soundboard pads, other
        --scenes' elements; ChatItemLinks).
        itemLinkDragHover = function(element, items)
            if items == nil then
                DestroyGhost()
            else
                ShowGhost(DroppableItem(items))
            end
        end,
        itemLinkDrop = function(element, items)
            TakeDrop(items)
        end,

        --map tokens dragged off the board.
        tokenDragEnter = function(element, info)
            ShowGhost(DroppableItem(CharacterItems(info.charids)))
        end,
        tokenDragLeave = function(element)
            DestroyGhost()
        end,
        dropTokens = function(element, info)
            TakeDrop(CharacterItems(info.charids))
        end,

        children = {m_fxLayer, m_speechLayer},
    }
    g_layers[layer] = true
    return layer
end
