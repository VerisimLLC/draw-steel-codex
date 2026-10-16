local mod = dmhub.GetModLoading()

--Image and video files dragged from the desktop onto the bare table
--(Tabletop.lua's TableFilesDropped, Director only) open this dialog: "Add
--Image", "Add Video" or "Add 4 Images". It lists what the files can become --
--a map, scenes, or the pictures themselves on the table -- and suggests one
--from their sizes: a whole number of 140-pixel squares is a map, a big
--widescreen picture is a scene, anything else stays a picture.
--
--Pictures and videos put on the table are journal image entries (in the
--Director's private folder) shown as journal items (Tabletop.lua's "Journal
--entries on the table"), so they share, open, dock and drag into chat and
--journals like any journal item. What an entry cannot carry -- a video's
--loop and audio choices, and the file's real size before its asset has
--loaded -- goes in the shared "tablemedia" document, keyed by entry id, so
--every client draws them the same (TableMedia below).

--- @class TableMedia
TableMedia = {}

--- @class TableDropDialog
TableDropDialog = {}

--At most this many files are taken from one drop.
local MAX_FILES = 10

--Map art is made at 140 pixels per square by most creators (the map import
--wizard's "perfect fit" uses the same test). A map is at least this many
--squares on its short side, so a token or portrait is not taken for one.
local MAP_PIXELS_PER_SQUARE = 140
local MIN_MAP_SQUARES = 8
local MAX_MAP_SQUARES = 2000

--A scene: at least this wide, landscape, and within SCENE_TOLERANCE of
--16:9 or 16:10.
local SCENE_MIN_WIDTH = 1600
local SCENE_ASPECTS = {16 / 9, 16 / 10}
local SCENE_TOLERANCE = 0.03

--A video this short (seconds) is suggested as looping art with no sound; a
--longer one plays once, with its sound and a play bar.
local SHORT_VIDEO_SECONDS = 30

--How wide a picture lands on the table: alone, or one of several laid out.
local DROP_WIDTH_SINGLE = 400
local DROP_WIDTH_MULTI = 260

--The table item's own width (Tabletop.lua's DOC_PICTURE_WIDTH), and a
--video's, wider so its play bar fits.
local PICTURE_BASE_WIDTH = 200
local VIDEO_BASE_WIDTH = 400

--Words in file names that mark several images as the floors of one map
--rather than versions of it.
local FLOOR_WORDS = {"floor", "level", "lvl", "storey", "story", "upstairs", "downstairs", "upper", "lower",
    "basement", "cellar", "ground", "roof", "attic", "loft"}

local DIALOG_WIDTH = 820
local PAD = 28
local PREVIEW_SIZE = 264
local OPTIONS_WIDTH = DIALOG_WIDTH - PAD * 2 - PREVIEW_SIZE - PAD
local ICON_BOX = 46
local RADIO_SIZE = 22
local OPTION_HPAD = 16
local OPTION_TEXT_WIDTH = OPTIONS_WIDTH - OPTION_HPAD * 2 - ICON_BOX - 14 - RADIO_SIZE - 12

----------------------------------------------------------------------
--TableMedia: what the table knows about pictures and videos added here.

local MEDIA_DOC = "tablemedia"

--Local file paths of entries added this session, on this machine only: a
--video becomes a map from its file (a cached video has no usable path).
local g_localPaths = {}

--- @class TableMediaInfo
--- @field width number the file's size in pixels (0 if unknown)
--- @field height number
--- @field video boolean
--- @field loop boolean a video loops with no play bar, rather than playing once
--- @field audio boolean a video plays its sound

--- What the table knows about a journal image entry added from the desktop,
--- or nil for any other entry.
--- @param entryid nil|string
--- @return nil|TableMediaInfo
function TableMedia.Info(entryid)
    if type(entryid) ~= "string" then
        return nil
    end
    local items = mod:GetDocumentSnapshot(MEDIA_DOC).data.items
    if type(items) ~= "table" then
        return nil
    end
    local info = items[entryid]
    if type(info) ~= "table" then
        return nil
    end
    return {
        width = tonumber(info.width) or 0,
        height = tonumber(info.height) or 0,
        video = info.video == true,
        loop = info.loop ~= false,
        audio = info.audio == true,
    }
end

--- True for a journal entry that is a video (added here or not).
--- @param entryid nil|string
--- @return boolean
function TableMedia.IsVideo(entryid)
    if type(entryid) ~= "string" then
        return false
    end
    local info = TableMedia.Info(entryid)
    if info ~= nil then
        return info.video
    end
    return FullscreenDisplay.IsVideo(entryid)
end

--- True for a video that plays once with a play bar, which takes clicks.
--- @param entryid nil|string
--- @return boolean
function TableMedia.HasControls(entryid)
    if not TableMedia.IsVideo(entryid) then
        return false
    end
    local info = TableMedia.Info(entryid)
    return info ~= nil and not info.loop
end

--- The width a table item for this entry is laid out at before its scale, or
--- nil for the usual picture width.
--- @param entryid nil|string
--- @return nil|number
function TableMedia.BaseWidth(entryid)
    if TableMedia.IsVideo(entryid) then
        return VIDEO_BASE_WIDTH
    end
    return nil
end

--Records several entries in one change. records: entryid -> fields.
local function RecordMedia(records)
    local doc = mod:GetDocumentSnapshot(MEDIA_DOC)
    doc:BeginChange()
    if type(doc.data.items) ~= "table" then
        doc.data.items = {}
    end
    for entryid, fields in pairs(records) do
        doc.data.items[entryid] = fields
    end
    doc:CompleteChange("Add to the table", {undoable = false})
end

--- The face of a video table item at w x h: looping art, or (playing once)
--- the journal's video control with its play bar.
--- @param entryid string
--- @param w number
--- @param h number
--- @return Panel
function TableMedia.VideoFace(entryid, w, h)
    local info = TableMedia.Info(entryid)
    local loop = info == nil or info.loop
    local audio = info ~= nil and info.audio

    local content
    if loop then
        content = gui.Panel{
            width = w - 4,
            height = h - 4,
            halign = "center",
            valign = "center",
            bgcolor = "white",
            cornerRadius = 5,
            interactable = false,
            --its own looping player ("###" gives this panel its own instance).
            create = function(element)
                element.bgimageStreamed = entryid .. cond(audio, "###LOOPAUDIO", "###LOOP") .. dmhub.GenerateGuid()
            end,
        }
    else
        local tag = RichVideo.new{
            image = entryid,
            loop = false,
            autoplay = false,
            audio = audio,
            maxWidth = w - 4,
            halign = "center",
        }
        content = gui.Panel{
            width = w - 4,
            height = h - 4,
            halign = "center",
            valign = "center",
            flow = "none",
            --the table carries no theme, and the play bar's sizes and colours
            --are theme classes (as in a document, where the journal brings it).
            styles = ThemeEngine.GetStyles(),
            --the control takes its source from a refreshTag, as in a document.
            create = function(element)
                element:FireEventTree("refreshTag", tag, nil, {})
            end,
            RichVideo.CreateDisplay(tag),
        }
    end

    return gui.Panel{
        classes = {"tabletopDocFace"},
        bgimage = "panels/square.png",
        width = w,
        height = h,
        flow = "none",
        interactable = not loop,
        content,
    }
end

--Waits (up to half a minute) for a just-uploaded entry to reach the journal,
--then puts it on the table.
local function PlaceWhenReady(entryid, at, scale)
    dmhub.Coroutine(function()
        local deadline = dmhub.Time() + 30
        while CustomDocument.FindJournalEntry(entryid) == nil do
            if mod.unloaded or dmhub.Time() > deadline then
                return
            end
            coroutine.yield(0.1)
        end
        if mod.unloaded then
            return
        end
        Tabletop.OpenDocItem(entryid, {at = at, scale = scale})
    end)
end

--The entry's name, for the map or scene made from it.
local function EntryName(entryid, fallback)
    local entry = CustomDocument.FindJournalEntry(entryid)
    if entry ~= nil and type(entry.description) == "string" and entry.description ~= "" then
        return entry.description
    end
    return fallback
end

--- Makes a scene from a picture or video entry and opens it at (mx, my) on
--- the table. Returns true when it did.
--- @param entryid string
--- @param mx number
--- @param my number
--- @return boolean
function TableMedia.ConvertToScene(entryid, mx, my)
    local sceneid = Scenes.Create{
        name = EntryName(entryid, "New Scene"),
        image = entryid,
    }
    Tabletop.OpenSceneCentredAt(sceneid, mx, my)
    return true
end

--- Makes a map from a picture or video entry through the import wizard,
--- named after the entry; its window opens at (mx, my) on the table. A
--- picture comes from its cached copy; a video only from the file it was
--- added from this session. created (optional) is called once the map exists
--- (not if the wizard is cancelled). Returns true when the wizard opened.
--- @param entryid string
--- @param mx number
--- @param my number
--- @param created nil|fun(mapid: string)
--- @return boolean
function TableMedia.ConvertToMap(entryid, mx, my, created)
    local path = g_localPaths[entryid]
    local video = TableMedia.IsVideo(entryid)
    if path == nil and not video then
        local asset = assets.imagesTable[entryid] --[[@as nil|AssetImageBaseLua]]
        if asset ~= nil then
            path = asset.cachePath
        end
    end

    if path == nil then
        gui.ModalMessage{
            title = "Can't Make a Map Yet",
            message = cond(video,
                "Drag the video file onto the table again and choose Map.",
                "This picture hasn't finished downloading. Try again in a moment."),
        }
        return false
    end

    local aspect = nil
    local info = TableMedia.Info(entryid)
    if info ~= nil and info.width > 0 and info.height > 0 then
        aspect = info.width / info.height
    else
        local entry = CustomDocument.FindJournalEntry(entryid)
        local w = entry ~= nil and tonumber(entry.width) or 0
        local h = entry ~= nil and tonumber(entry.height) or 0
        if w > 0 and h > 0 then
            aspect = w / h
        end
    end
    Tabletop.AddFilesAsMap({path}, mx, my, {aspect = aspect, name = EntryName(entryid, "New Map"), created = created})
    return true
end

----------------------------------------------------------------------
--Reading the dropped files and deciding what they look like.

--- @class TableDropFile
--- @field path string
--- @field name string
--- @field video boolean
--- @field width number 0 until known
--- @field height number
--- @field bytes nil|number
--- @field duration nil|number a video's length in seconds, once read
--- @field known boolean its size has been read (or can't be)
--- @field preview nil|string a small local image of it
--- @field previewTried boolean

--- @param paths string[]
--- @return TableDropFile[]
local function ReadFiles(paths)
    local files = {}
    for _, path in ipairs(paths) do
        if #files >= MAX_FILES then
            break
        end
        local file = {
            path = path,
            name = FileDrops.BaseName(path),
            video = FileDrops.IsVideo(path),
            width = 0,
            height = 0,
            known = false,
            previewTried = false,
        }
        if not file.video then
            --the header alone: instant even for a huge map.
            local info = assets:ReadImageFileInfo(path)
            if info ~= nil then
                file.width = info.width
                file.height = info.height
                file.bytes = info.bytes
            end
            file.known = true
        end
        files[#files+1] = file
    end
    return files
end

--The map size in squares a picture of w x h pixels fits exactly, or nil.
local function MapFit(w, h)
    if w <= 0 or h <= 0 then
        return nil, nil
    end
    local tw = w / MAP_PIXELS_PER_SQUARE
    local th = h / MAP_PIXELS_PER_SQUARE
    if math.abs(tw - math.floor(tw + 0.5)) > 0.01 or math.abs(th - math.floor(th + 0.5)) > 0.01 then
        return nil, nil
    end
    tw = math.floor(tw + 0.5)
    th = math.floor(th + 0.5)
    if math.min(tw, th) < MIN_MAP_SQUARES or math.max(tw, th) > MAX_MAP_SQUARES then
        return nil, nil
    end
    return tw, th
end

local function LooksLikeScene(w, h)
    if w < SCENE_MIN_WIDTH or h <= 0 or w < h then
        return false
    end
    local aspect = w / h
    for _, target in ipairs(SCENE_ASPECTS) do
        if math.abs(aspect - target) / target <= SCENE_TOLERANCE then
            return true
        end
    end
    return false
end

local function NamesSayFloors(files)
    for _, file in ipairs(files) do
        local name = string.lower(file.name)
        for _, word in ipairs(FLOOR_WORDS) do
            if string.find(name, word, 1, true) ~= nil then
                return true
            end
        end
    end
    return false
end

--- @class TableDropAnalysis
--- @field count number
--- @field videos number
--- @field allKnown boolean
--- @field sameSize boolean every file is the same, known size
--- @field mapW nil|number the squares the files fit as a map
--- @field mapH nil|number
--- @field scenes boolean every file looks like a scene
--- @field suggestion string the option to start on

--- @param files TableDropFile[]
--- @return TableDropAnalysis
local function Analyse(files)
    local a = {count = #files, videos = 0, allKnown = true, sameSize = true, scenes = true, suggestion = "images"}
    local first = files[1]
    for _, file in ipairs(files) do
        if file.video then
            a.videos = a.videos + 1
        end
        if not file.known then
            a.allKnown = false
        end
        if file.width <= 0 or file.width ~= first.width or file.height ~= first.height then
            a.sameSize = false
        end
        if not LooksLikeScene(file.width, file.height) then
            a.scenes = false
        end
    end
    if not a.allKnown then
        a.sameSize = false
        a.scenes = false
    end
    if a.sameSize then
        a.mapW, a.mapH = MapFit(first.width, first.height)
    end

    if a.mapW ~= nil then
        if a.count == 1 then
            a.suggestion = "map"
        elseif NamesSayFloors(files) then
            a.suggestion = "floors"
        else
            a.suggestion = "variations"
        end
    elseif a.scenes then
        a.suggestion = "scenes"
    end
    return a
end

----------------------------------------------------------------------
--The dialog.

--"Images", "Videos" or "Files", for n files of which videos are videos.
local function KindWord(n, videos, single)
    if videos == 0 then
        return cond(single, "Image", "Images")
    elseif videos == n then
        return cond(single, "Video", "Videos")
    end
    return "Files"
end

local function FormatBytes(bytes)
    if bytes == nil then
        return nil
    end
    if bytes >= 1024 * 1024 then
        return string.format("%.1f MB", bytes / (1024 * 1024))
    end
    return string.format("%d KB", math.max(1, math.floor(bytes / 1024 + 0.5)))
end

local function FormatDuration(seconds)
    if seconds == nil or seconds <= 0 then
        return nil
    end
    local s = math.floor(seconds + 0.5)
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function DialogStyles()
    return {
        {
            selectors = {"tableDropTitle"},
            fontSize = 30,
            bold = true,
            color = "@fgStrong",
        },
        {
            selectors = {"tableDropMuted"},
            color = "@fgMuted",
        },
        {
            selectors = {"tableDropStrong"},
            color = "@fgStrong",
        },
        {
            selectors = {"tableDropAccent"},
            color = "@info",
        },
        {
            selectors = {"tableDropRule"},
            bgcolor = "@borderSolid",
        },
        {
            selectors = {"tableDropPreviewBox"},
            bgcolor = "@bg",
            borderColor = "@borderSolid",
            borderWidth = 1,
            cornerRadius = 8,
        },
        {
            selectors = {"tableDropPreviewFrame"},
            borderColor = "@info",
            borderWidth = 1,
        },
        {
            selectors = {"tableDropClose"},
            bgcolor = "clear",
            cornerRadius = 8,
        },
        {
            selectors = {"tableDropClose", "hover"},
            bgcolor = "@bgAlt",
        },
        {
            selectors = {"tableDropCloseIcon"},
            bgcolor = "@fgMuted",
        },
        {
            selectors = {"tableDropOption"},
            bgcolor = "@bg",
            borderColor = "@borderSolid",
            borderWidth = 1,
            cornerRadius = 10,
            transitionTime = 0.12,
        },
        {
            selectors = {"tableDropOption", "hover"},
            bgcolor = "@bgAlt",
            transitionTime = 0.12,
        },
        {
            selectors = {"tableDropOption", "selected"},
            bgcolor = "@bgAlt",
            borderColor = "@fg",
            borderWidth = 2,
            transitionTime = 0.12,
        },
        {
            selectors = {"tableDropIconBox"},
            bgcolor = "@bgAlt",
            borderColor = "@borderSolid",
            borderWidth = 1,
            cornerRadius = 9,
        },
        {
            selectors = {"tableDropIcon"},
            bgcolor = "@fg",
        },
        {
            selectors = {"tableDropPill"},
            bgcolor = "clear",
            borderColor = "@info",
            borderWidth = 1,
            cornerRadius = 9,
        },
        {
            selectors = {"tableDropCallout"},
            bgcolor = "@bg",
            borderColor = "@info",
            borderWidth = 1,
            cornerRadius = 7,
        },
        {
            selectors = {"tableDropCalloutIcon"},
            bgcolor = "@info",
        },
        {
            selectors = {"tableDropRadio"},
            bgcolor = "clear",
            borderColor = "@fgMuted",
            borderWidth = 1.5,
            cornerRadius = RADIO_SIZE / 2,
        },
        {
            selectors = {"tableDropRadio", "selected"},
            borderColor = "@fgStrong",
            borderWidth = 2,
        },
        {
            selectors = {"tableDropRadioDot"},
            bgcolor = "@fgStrong",
            cornerRadius = 5,
            opacity = 0,
        },
        {
            selectors = {"tableDropRadioDot", "selected"},
            opacity = 1,
        },
    }
end

--Lays several pictures out in a grid centred on (mx, my): the centre of
--each, in the table's units, for items of the given widths and heights.
local function GridPositions(sizes, mx, my)
    local n = #sizes
    local cols = math.ceil(math.sqrt(n))
    local rows = math.ceil(n / cols)
    local GAP = 28
    local cellW = 0
    local rowHeights = {}
    for i, size in ipairs(sizes) do
        cellW = math.max(cellW, size.w)
        local row = math.floor((i - 1) / cols) + 1
        rowHeights[row] = math.max(rowHeights[row] or 0, size.h)
    end
    local totalW = cols * cellW + (cols - 1) * GAP
    local totalH = (rows - 1) * GAP
    for r = 1, rows do
        totalH = totalH + rowHeights[r]
    end
    --the whole grid stays on the table (room above for the items' titlebars).
    local area = Tabletop.LayerRect()
    local left = math.max(16, math.min(mx - totalW / 2, area.w - totalW - 16))
    local top = math.max(40, math.min(my - totalH / 2, area.h - totalH - 16))
    local result = {}
    local y = top
    for r = 1, rows do
        local x = left
        for c = 1, cols do
            local i = (r - 1) * cols + c
            if i <= n then
                result[i] = {x = math.floor(x + cellW / 2), y = math.floor(y + rowHeights[r] / 2)}
            end
            x = x + cellW + GAP
        end
        y = y + rowHeights[r] + GAP
    end
    return result
end

--Puts the files on the table as journal pictures and videos, laid out
--around (mx, my).
local function AddToTable(files, mx, my, loop, audio)
    local targetW = cond(#files == 1, DROP_WIDTH_SINGLE, DROP_WIDTH_MULTI)
    local records = {}
    local placements = {}
    local sizes = {}
    for _, file in ipairs(files) do
        local entryid = FileDrops.UploadImage(file.path, {imageType = "document", parentFolder = "private"})
        if entryid ~= nil then
            g_localPaths[entryid] = file.path
            records[entryid] = {
                width = file.width,
                height = file.height,
                video = file.video,
                loop = loop,
                audio = audio,
            }
            local baseW = cond(file.video, VIDEO_BASE_WIDTH, PICTURE_BASE_WIDTH)
            local scale = targetW / baseW
            local aspect = 1
            if file.width > 0 and file.height > 0 then
                aspect = math.max(0.4, math.min(1.6, file.height / file.width))
            end
            placements[#placements+1] = {entryid = entryid, scale = scale}
            sizes[#sizes+1] = {w = targetW, h = targetW * aspect}
        end
    end
    if #placements == 0 then
        return
    end
    RecordMedia(records)
    local positions = GridPositions(sizes, mx, my)
    for i, placement in ipairs(placements) do
        PlaceWhenReady(placement.entryid, positions[i], placement.scale)
    end
end

--- Shows the Add Image / Add Video dialog for files dropped on the table at
--- (mx, my), in the table's units.
--- @param paths string[] local image and video files
--- @param mx number
--- @param my number
function TableDropDialog.Show(paths, mx, my)
    local files = ReadFiles(paths)
    if #files == 0 then
        return
    end
    local dropped = #paths

    local state = {
        analysis = Analyse(files),
        selected = nil,
        --the Director picked an option or changed the video settings: what
        --arrives later (a video's size) no longer changes them.
        picked = false,
        videoSet = false,
        videoDefaulted = false,
        loop = true,
        audio = false,
    }
    state.selected = state.analysis.suggestion

    local single = #files == 1
    local first = files[1]

    local dialog
    local optionsPanel
    local previewPanel
    local primaryButton

    local Refresh
    local RebuildOptions

    --what each option is called, says and does, for this drop.
    local function OptionList()
        local a = state.analysis
        local n = a.count
        local list = {}

        local mapCallout = nil
        if a.mapW ~= nil then
            if single then
                mapCallout = {
                    bold = string.format("This looks like a <nobr>%d x %d</nobr> map.", a.mapW, a.mapH),
                    text = "At 140 pixels per square it fits the grid exactly, the size map creators most often use.",
                }
            else
                mapCallout = {
                    bold = string.format("These look like <nobr>%d x %d</nobr> maps.", a.mapW, a.mapH),
                    text = string.format("All %d are <nobr>%d x %d</nobr> pixels: exactly 140 pixels per square, the size map creators most often use.",
                        n, first.width, first.height),
                }
            end
        end

        if single then
            list[#list+1] = {
                id = "map",
                icon = "phosphor/map-trifold.png",
                title = "Map",
                text = cond(a.mapW ~= nil,
                    "A playable map with a grid, tokens and fog of war. Its window opens showing the whole map.",
                    "A playable map with a grid, tokens and fog of war. You'll set the grid size next."),
                callout = mapCallout,
            }
        else
            list[#list+1] = {
                id = "floors",
                icon = "phosphor/stack-plus.png",
                title = string.format("Map with %d Floors", n),
                text = "One map with a floor for each file, in the order shown. You'll set the grid next.",
                callout = cond(a.suggestion == "floors", mapCallout, nil),
            }
            if a.sameSize then
                list[#list+1] = {
                    id = "variations",
                    icon = "phosphor/swap.png",
                    title = string.format("Map with %d Variations", n),
                    text = "One map you can switch between versions of, like day and night or with and without a grid.",
                    callout = cond(a.suggestion == "variations", mapCallout, nil),
                }
            end
        end

        local sceneCallout = nil
        if a.scenes then
            sceneCallout = {
                bold = cond(single, "This looks like a scene.", "These look like scenes."),
                text = string.format("<nobr>%d x %d</nobr> is a widescreen %s, the shape scene art is made in.",
                    first.width, first.height, cond(a.videos > 0, "video", "picture")),
            }
        end
        list[#list+1] = {
            id = "scenes",
            icon = "phosphor/mountains.png",
            title = cond(single, "Scene", string.format("%d Scenes", n)),
            text = cond(single,
                "Art for setting the mood, in its own window or full screen for your players.",
                "Each one a scene in the Scenes library, in its own window, to show your players."),
            callout = sceneCallout,
        }

        local kind = KindWord(n, a.videos, single)
        local text
        if single and a.videos == 0 then
            text = "Just the picture, on the table. Share it with players or drag it into a journal; make it a map or scene later."
        elseif single then
            text = "The video itself, on the table, to share with players. Make it a map or scene later."
        else
            text = "Laid out on the table where you dropped them, to share with players or drag into a journal."
        end
        list[#list+1] = {
            id = "images",
            icon = cond(a.videos > 0 and a.videos == n, "phosphor/film-strip.png", cond(single, "phosphor/image.png", "phosphor/squares-four.png")),
            title = cond(single, kind, string.format("%d %s", n, kind)),
            text = text,
            videoSettings = a.videos > 0,
        }
        return list
    end

    local function Select(id)
        state.selected = id
        state.picked = true
        Refresh()
    end

    local function OptionRow(option, count)
        --only a real detection is suggested; plain pictures are just the default.
        local pill = nil
        if option.id == state.analysis.suggestion and option.id ~= "images" and count > 1 then
            pill = gui.Panel{
                classes = {"tableDropPill"},
                bgimage = "panels/square.png",
                width = "auto",
                height = "auto",
                valign = "center",
                lmargin = 10,
                hpad = 9,
                vpad = 2,
                borderBox = true,
                interactable = false,
                gui.Label{
                    classes = {"tableDropAccent"},
                    text = "SUGGESTED",
                    fontSize = 11,
                    bold = true,
                    width = "auto",
                    height = "auto",
                    interactable = false,
                },
            }
        end

        local callout = nil
        if option.callout ~= nil then
            callout = gui.Panel{
                classes = {"tableDropCallout"},
                bgimage = "panels/square.png",
                width = OPTION_TEXT_WIDTH,
                height = "auto",
                flow = "horizontal",
                tmargin = 10,
                hpad = 12,
                vpad = 10,
                borderBox = true,
                interactable = false,
                gui.Panel{
                    classes = {"tableDropCalloutIcon"},
                    bgimage = "phosphor/check-circle-fill.png",
                    width = 18,
                    height = 18,
                    valign = "top",
                    tmargin = 2,
                    rmargin = 10,
                    interactable = false,
                },
                gui.Label{
                    width = OPTION_TEXT_WIDTH - 24 - 28,
                    height = "auto",
                    fontSize = 15,
                    textWrap = true,
                    interactable = false,
                    text = string.format("<b>%s</b> %s", option.callout.bold, option.callout.text),
                },
            }
        end

        local radioDot = gui.Panel{
            classes = {"tableDropRadioDot"},
            bgimage = "panels/square.png",
            width = 10,
            height = 10,
            halign = "center",
            valign = "center",
            interactable = false,
        }
        local radio = gui.Panel{
            classes = {"tableDropRadio"},
            bgimage = "panels/square.png",
            width = RADIO_SIZE,
            height = RADIO_SIZE,
            valign = "top",
            tmargin = 12,
            lmargin = 12,
            interactable = false,
            radioDot,
        }

        local row
        row = gui.Panel{
            classes = {"tableDropOption"},
            bgimage = "panels/square.png",
            width = OPTIONS_WIDTH,
            height = "auto",
            flow = "horizontal",
            hpad = OPTION_HPAD,
            vpad = 14,
            borderBox = true,
            press = function(element)
                Select(option.id)
            end,
            refreshDrop = function(element)
                local on = state.selected == option.id
                element:SetClass("selected", on)
                radio:SetClass("selected", on)
                radioDot:SetClass("selected", on)
            end,
            gui.Panel{
                classes = {"tableDropIconBox"},
                bgimage = "panels/square.png",
                width = ICON_BOX,
                height = ICON_BOX,
                valign = "top",
                rmargin = 14,
                interactable = false,
                gui.Panel{
                    classes = {"tableDropIcon"},
                    bgimage = option.icon,
                    width = 24,
                    height = 24,
                    halign = "center",
                    valign = "center",
                    interactable = false,
                },
            },
            gui.Panel{
                width = OPTION_TEXT_WIDTH,
                height = "auto",
                flow = "vertical",
                valign = "top",
                interactable = false,
                gui.Panel{
                    width = "auto",
                    height = "auto",
                    flow = "horizontal",
                    halign = "left",
                    interactable = false,
                    gui.Label{
                        classes = {"tableDropStrong"},
                        text = option.title,
                        fontSize = 21,
                        bold = true,
                        width = "auto",
                        height = "auto",
                        valign = "center",
                        interactable = false,
                    },
                    pill,
                },
                gui.Label{
                    classes = {"tableDropMuted"},
                    text = option.text,
                    width = OPTION_TEXT_WIDTH,
                    height = "auto",
                    fontSize = 15,
                    textWrap = true,
                    tmargin = 3,
                    halign = "left",
                    interactable = false,
                },
                callout,
            },
            radio,
        }
        return row
    end

    --Loop and Include Audio for the videos, under the pictures option while
    --it is chosen.
    local function VideoSettings()
        local hint
        hint = gui.Label{
            classes = {"tableDropMuted"},
            width = OPTIONS_WIDTH - 60,
            height = "auto",
            fontSize = 14,
            textWrap = true,
            tmargin = 4,
            refreshDrop = function(element)
                element.text = cond(state.loop,
                    "Loops like animated art, with no play bar.",
                    "Plays once, with play, pause and a scrub bar.")
            end,
        }
        return gui.Panel{
            width = OPTIONS_WIDTH,
            height = "auto",
            flow = "vertical",
            lmargin = 0,
            hpad = 60,
            borderBox = true,
            tmargin = 2,
            bmargin = 2,
            refreshDrop = function(element)
                element:SetClass("collapsed", state.selected ~= "images")
            end,
            gui.Panel{
                width = "auto",
                height = "auto",
                flow = "horizontal",
                halign = "left",
                gui.Check{
                    text = "Loop",
                    value = state.loop,
                    width = 120,
                    halign = "left",
                    hover = gui.Tooltip("Plays over and over with no play bar. Untick to play once, with play, pause and a scrub bar."),
                    refreshDrop = function(element)
                        if element.value ~= state.loop then
                            element.value = state.loop
                        end
                    end,
                    change = function(element)
                        if element.value == state.loop then
                            return
                        end
                        state.loop = element.value
                        state.videoSet = true
                        Refresh()
                    end,
                },
                gui.Check{
                    text = "Include audio",
                    value = state.audio,
                    width = 180,
                    halign = "left",
                    hover = gui.Tooltip("Plays the video's sound. Maps and scenes never do."),
                    refreshDrop = function(element)
                        if element.value ~= state.audio then
                            element.value = state.audio
                        end
                    end,
                    change = function(element)
                        if element.value == state.audio then
                            return
                        end
                        state.audio = element.value
                        state.videoSet = true
                        Refresh()
                    end,
                },
            },
            hint,
        }
    end

    RebuildOptions = function()
        local children = {}
        local list = OptionList()
        for _, option in ipairs(list) do
            children[#children+1] = OptionRow(option, #list)
            if option.videoSettings then
                children[#children+1] = VideoSettings()
            end
        end
        optionsPanel.children = children
    end

    --The picture box: one picture fitted inside it (with the map's grid
    --over it while Map is chosen), or a grid of thumbnails for several.
    local function PreviewImage(file, boxW, boxH, withGrid)
        local w, h = boxW, boxH
        if file.width > 0 and file.height > 0 then
            local s = math.min(boxW / file.width, boxH / file.height)
            w = math.max(8, math.floor(file.width * s))
            h = math.max(8, math.floor(file.height * s))
        end
        local children = {}
        if withGrid and state.analysis.mapW ~= nil then
            local tw, th = state.analysis.mapW, state.analysis.mapH
            --a line per square when they are big enough to see, else every few.
            local step = math.max(1, math.ceil(4 / math.max(0.01, w / tw)))
            local lines = {}
            for i = step, tw - 1, step do
                lines[#lines+1] = gui.Panel{
                    floating = true,
                    halign = "left",
                    valign = "top",
                    x = math.floor(i * w / tw),
                    y = 0,
                    width = 1,
                    height = h,
                    bgimage = "panels/square.png",
                    bgcolor = "#00000066",
                    interactable = false,
                }
            end
            for i = step, th - 1, step do
                lines[#lines+1] = gui.Panel{
                    floating = true,
                    halign = "left",
                    valign = "top",
                    x = 0,
                    y = math.floor(i * h / th),
                    width = w,
                    height = 1,
                    bgimage = "panels/square.png",
                    bgcolor = "#00000066",
                    interactable = false,
                }
            end
            lines[#lines+1] = gui.Panel{
                classes = {"tableDropPreviewFrame"},
                floating = true,
                bgimage = "panels/square.png",
                bgcolor = "clear",
                width = w,
                height = h,
                interactable = false,
            }
            children[#children+1] = gui.Panel{
                floating = true,
                width = w,
                height = h,
                flow = "none",
                interactable = false,
                refreshDrop = function(element)
                    element:SetClass("collapsed", state.selected ~= "map")
                end,
                children = lines,
            }
        end

        if file.preview == nil then
            --not read yet (or unreadable): its kind's glyph.
            children[#children+1] = gui.Panel{
                classes = {"tableDropIcon"},
                bgimage = cond(file.video, "phosphor/film-strip.png", "phosphor/image.png"),
                width = math.min(40, math.floor(w / 2)),
                height = math.min(40, math.floor(w / 2)),
                halign = "center",
                valign = "center",
                interactable = false,
            }
            return gui.Panel{
                classes = {"tableDropIconBox"},
                bgimage = "panels/square.png",
                width = w,
                height = h,
                halign = "center",
                valign = "center",
                flow = "none",
                interactable = false,
                children = children,
            }
        end

        return gui.Panel{
            bgimage = file.preview,
            bgcolor = "white",
            width = w,
            height = h,
            halign = "center",
            valign = "center",
            flow = "none",
            interactable = false,
            children = children,
        }
    end

    local function BuildPreview()
        local box
        if single then
            box = PreviewImage(first, PREVIEW_SIZE - 28, PREVIEW_SIZE - 28, true)
        else
            --as big as fits: 2 across for up to 4, 3 for up to 9, then 4.
            local cols = 4
            if #files <= 4 then
                cols = 2
            elseif #files <= 9 then
                cols = 3
            end
            local rows = math.ceil(#files / cols)
            local cell = math.floor((PREVIEW_SIZE - 20) / math.max(cols, rows)) - 6
            local thumbs = {}
            for _, file in ipairs(files) do
                thumbs[#thumbs+1] = gui.Panel{
                    width = cell,
                    height = cell,
                    hmargin = 3,
                    vmargin = 3,
                    flow = "none",
                    interactable = false,
                    PreviewImage(file, cell, cell, false),
                }
            end
            box = gui.Panel{
                width = cols * (cell + 6),
                height = "auto",
                halign = "center",
                valign = "center",
                flow = "horizontal",
                wrap = true,
                interactable = false,
                children = thumbs,
            }
        end

        local details = {}
        if single then
            if first.width > 0 then
                details[#details+1] = string.format("%d x %d px", first.width, first.height)
            elseif first.video and not first.known then
                details[#details+1] = "Reading the video..."
            end
            details[#details+1] = FormatDuration(first.duration)
            details[#details+1] = FormatBytes(first.bytes)
        else
            local total = 0
            local haveBytes = false
            for _, file in ipairs(files) do
                if file.bytes ~= nil then
                    total = total + file.bytes
                    haveBytes = true
                end
            end
            if state.analysis.sameSize then
                details[#details+1] = string.format("All %d x %d px", first.width, first.height)
            end
            if haveBytes then
                details[#details+1] = FormatBytes(total)
            end
        end

        local mapLine = nil
        if single and state.analysis.mapW ~= nil then
            mapLine = string.format("%d x %d squares at 140 px each", state.analysis.mapW, state.analysis.mapH)
        end

        local names = {}
        if single then
            names[1] = FileDrops.BaseName(first.path) .. FileDrops.Extension(first.path)
        else
            for i, file in ipairs(files) do
                if i > 3 then
                    names[#names+1] = string.format("and %d more", #files - 3)
                    break
                end
                names[#names+1] = file.name
            end
        end

        previewPanel.children = {
            gui.Panel{
                classes = {"tableDropPreviewBox"},
                bgimage = "panels/square.png",
                width = PREVIEW_SIZE,
                height = PREVIEW_SIZE,
                flow = "none",
                interactable = false,
                box,
            },
            gui.Label{
                classes = {"tableDropStrong"},
                text = table.concat(names, "\n"),
                width = PREVIEW_SIZE,
                height = "auto",
                fontSize = 17,
                bold = true,
                textWrap = true,
                tmargin = 14,
            },
            gui.Label{
                classes = {"tableDropMuted"},
                text = table.concat(details, "  -  "),
                width = PREVIEW_SIZE,
                height = "auto",
                fontSize = 15,
                tmargin = 3,
            },
            mapLine and gui.Label{
                classes = {"tableDropAccent"},
                text = mapLine,
                width = PREVIEW_SIZE,
                height = "auto",
                fontSize = 15,
                tmargin = 2,
                refreshDrop = function(element)
                    element:SetClass("collapsed", state.selected ~= "map")
                end,
            } or nil,
        }
    end

    local function PrimaryText()
        local id = state.selected
        if id == "map" or id == "floors" or id == "variations" then
            return "Make Map"
        elseif id == "scenes" then
            return cond(single, "Add as Scene", "Add as Scenes")
        end
        return "Add to Table"
    end

    Refresh = function()
        if dialog == nil or not dialog.valid then
            return
        end
        dialog:FireEventTree("refreshDrop")
        primaryButton.text = PrimaryText()
    end

    --a file's size or picture arrived: re-read the drop, and follow the new
    --suggestion unless the Director already chose.
    local function FilesChanged(reanalyse)
        if dialog == nil or not dialog.valid then
            return
        end
        if reanalyse then
            state.analysis = Analyse(files)
            if not state.picked then
                state.selected = state.analysis.suggestion
            end
            RebuildOptions()
        end
        BuildPreview()
        Refresh()
    end

    local function Commit()
        local id = state.selected
        local paths = {}
        for _, file in ipairs(files) do
            paths[#paths+1] = file.path
        end
        local aspect = nil
        if first.width > 0 and first.height > 0 then
            aspect = first.width / first.height
        end
        if id == "map" then
            Tabletop.AddFilesAsMap({first.path}, mx, my, {aspect = aspect})
        elseif id == "floors" then
            Tabletop.AddFilesAsMap(paths, mx, my, {aspect = aspect})
        elseif id == "variations" then
            local rest = {}
            for i = 2, #paths do
                rest[#rest+1] = paths[i]
            end
            Tabletop.AddFilesAsMap({first.path}, mx, my, {aspect = aspect, variations = rest})
        elseif id == "scenes" then
            Tabletop.AddFilesAsScenes(paths, mx, my)
        else
            AddToTable(files, mx, my, state.loop, state.audio)
        end
    end

    local title = string.format("Add %s", cond(single, KindWord(1, state.analysis.videos, true),
        string.format("%d %s", #files, KindWord(#files, state.analysis.videos, false))))

    local tip = "Drop it on a map window instead to place it on that map."
    if dropped > MAX_FILES then
        tip = string.format("Only the first %d of the %d files are added.", MAX_FILES, dropped)
    elseif not single then
        tip = "Drop them on a map window instead to place them on that map."
    end

    optionsPanel = gui.Panel{
        width = OPTIONS_WIDTH,
        height = "auto",
        flow = "vertical",
        valign = "top",
    }
    previewPanel = gui.Panel{
        width = PREVIEW_SIZE,
        height = "auto",
        flow = "vertical",
        valign = "top",
        rmargin = PAD,
    }

    primaryButton = gui.Button{
        classes = {"sizeM", "selected"},
        width = 170,
        text = PrimaryText(),
        click = function(element)
            gui.CloseModal()
            Commit()
        end,
    }

    dialog = gui.Panel{
        classes = {"framedPanel"},
        width = DIALOG_WIDTH,
        height = "auto",
        flow = "vertical",
        styles = ThemeEngine.MergeStyles(DialogStyles()),
        --pictures load one per tick once the dialog is up, so it opens at once.
        thinkTime = 0.05,
        think = function(element)
            for _, file in ipairs(files) do
                if not file.video and not file.previewTried then
                    file.previewTried = true
                    local loaded = assets:LoadImageFileLocallyResized(file.path, 600)
                    if loaded ~= nil then
                        file.preview = loaded.image
                    end
                    FilesChanged(false)
                    return
                end
            end
        end,

        gui.Panel{
            width = DIALOG_WIDTH,
            height = "auto",
            flow = "horizontal",
            hpad = PAD,
            tpad = 22,
            bpad = 18,
            borderBox = true,
            gui.Label{
                classes = {"tableDropTitle"},
                text = title,
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
            },
            gui.Panel{
                classes = {"tableDropClose"},
                bgimage = "panels/square.png",
                width = 36,
                height = 36,
                halign = "right",
                valign = "center",
                press = function(element)
                    gui.CloseModal()
                end,
                gui.Panel{
                    classes = {"tableDropCloseIcon"},
                    bgimage = "window-chrome/chrome-close.png",
                    width = 14,
                    height = 14,
                    halign = "center",
                    valign = "center",
                    interactable = false,
                },
            },
        },

        gui.Panel{
            classes = {"tableDropRule"},
            bgimage = "panels/square.png",
            width = DIALOG_WIDTH,
            height = 1,
        },

        gui.Panel{
            width = DIALOG_WIDTH,
            height = "auto",
            flow = "horizontal",
            hpad = PAD,
            vpad = 24,
            borderBox = true,
            previewPanel,
            gui.Panel{
                width = OPTIONS_WIDTH,
                height = "auto",
                flow = "vertical",
                valign = "top",
                gui.Label{
                    classes = {"tableDropMuted"},
                    text = "How should it go on the table?",
                    width = OPTIONS_WIDTH,
                    height = "auto",
                    fontSize = 15,
                    bmargin = 10,
                },
                optionsPanel,
            },
        },

        gui.Panel{
            classes = {"tableDropRule"},
            bgimage = "panels/square.png",
            width = DIALOG_WIDTH,
            height = 1,
        },

        gui.Panel{
            width = DIALOG_WIDTH,
            height = "auto",
            flow = "horizontal",
            hpad = PAD,
            vpad = 16,
            borderBox = true,
            gui.Label{
                classes = {"tableDropMuted"},
                text = tip,
                width = DIALOG_WIDTH - PAD * 2 - 170 - 140 - 20,
                height = "auto",
                fontSize = 14,
                textWrap = true,
                halign = "left",
                valign = "center",
            },
            gui.Panel{
                width = "auto",
                height = "auto",
                flow = "horizontal",
                halign = "right",
                valign = "center",
                gui.Button{
                    classes = {"sizeM"},
                    width = 130,
                    rmargin = 10,
                    text = "Cancel",
                    escapeActivates = true,
                    escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
                    click = function(element)
                        gui.CloseModal()
                    end,
                },
                primaryButton,
            },
        },
    }

    RebuildOptions()
    BuildPreview()
    gui.ShowModal(dialog)
    Refresh()

    --videos: their size, length and first frame, one after another (each
    --plays the file briefly).
    local function ReadNextVideo()
        for _, file in ipairs(files) do
            if file.video and not file.known then
                assets:ExtractVideoFrame{
                    path = file.path,
                    maxWidth = 600,
                    maxHeight = 600,
                    done = function(result)
                        file.known = true
                        file.width = result.videoWidth
                        file.height = result.videoHeight
                        file.duration = result.duration
                        file.preview = result.imageid
                        --the first video read sets the suggested Loop and Include Audio.
                        if not state.videoSet and not state.videoDefaulted and result.duration > 0 then
                            state.videoDefaulted = true
                            local short = result.duration <= SHORT_VIDEO_SECONDS
                            state.loop = short
                            state.audio = not short
                        end
                        if mod.unloaded then
                            return
                        end
                        FilesChanged(true)
                        ReadNextVideo()
                    end,
                    error = function(message)
                        file.known = true
                        if mod.unloaded then
                            return
                        end
                        FilesChanged(true)
                        ReadNextVideo()
                    end,
                }
                return
            end
        end
    end
    ReadNextVideo()
end
