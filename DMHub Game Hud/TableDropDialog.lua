local mod = dmhub.GetModLoading()

--Image and video files dragged from the desktop onto the bare table
--(Tabletop.lua's TableFilesDropped, Director only) open this dialog: "Add
--Image", "Add Video" or "Add 4 Images". It lists what the files can become --
--a map, scenes, or the pictures themselves on the table -- and suggests one:
--a picture with a grid is a map (a whole number of 140-pixel squares, or a
--grid the grid detector finds drawn on it -- MapGridDetection in
--MapImport.lua, which runs while the dialog is open), a big widescreen
--picture is a scene, anything else stays a picture.
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
--then puts it on the table, shared with the players if asked.
local function PlaceWhenReady(entryid, at, scale, shared)
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
        Tabletop.OpenDocItem(entryid, {at = at, scale = scale, placed = true})
        if shared then
            Tabletop.ShareDocItem(entryid)
        end
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

--Small local pictures of files read this session, keyed by path and size,
--so the drag card and then the dialog decode each file only once.
local g_previews = {}

--Gives a picture file its preview (decoded on the main thread: a moment for
--a big map), once.
--- @param file TableDropFile
local function LoadPreview(file)
    if file.video or file.previewTried then
        return
    end
    file.previewTried = true
    local key = string.format("%s|%s", file.path, tostring(file.bytes))
    local cached = g_previews[key]
    if cached == nil then
        local loaded = assets:LoadImageFileLocallyResized(file.path, 600)
        cached = (loaded ~= nil and loaded.image) or false
        g_previews[key] = cached
    end
    if cached then
        file.preview = cached
    end
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
--- @field grid nil|MapGridChoice the first picture's grid: a perfect fit or a detected grid
--- @field scenes boolean every file looks like a scene
--- @field suggestion string the option to start on

--- @param files TableDropFile[]
--- @param detection nil|false|ImageGridDetection the first file's grid detection, once done
--- @return TableDropAnalysis
local function Analyse(files, detection)
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
    --one picture, or several of one size (floors or versions of one map).
    if not first.video and first.width > 0 and (a.count == 1 or a.sameSize) then
        a.grid = MapGridDetection.Choose(first.width, first.height, detection, MIN_MAP_SQUARES)
    end

    if a.grid ~= nil then
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

--The size each picture or video is laid out at on the table, in the
--table's units: {w, h}.
--- @param files TableDropFile[]
--- @return {w: number, h: number}[]
local function LayoutSizes(files)
    local targetW = cond(#files == 1, DROP_WIDTH_SINGLE, DROP_WIDTH_MULTI)
    local sizes = {}
    for _, file in ipairs(files) do
        local aspect = 1
        if file.width > 0 and file.height > 0 then
            aspect = math.max(0.4, math.min(1.6, file.height / file.width))
        end
        sizes[#sizes+1] = {w = targetW, h = targetW * aspect}
    end
    return sizes
end

--Puts the files on the table as journal pictures and videos, laid out
--around (mx, my), shared with the players if asked.
local function AddToTable(files, mx, my, loop, audio, shared)
    local records = {}
    local placements = {}
    local uploaded = {}
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
            placements[#placements+1] = {entryid = entryid, video = file.video}
            uploaded[#uploaded+1] = file
        end
    end
    if #placements == 0 then
        return
    end
    RecordMedia(records)
    local sizes = LayoutSizes(uploaded)
    local positions = GridPositions(sizes, mx, my)
    for i, placement in ipairs(placements) do
        local scale = sizes[i].w / cond(placement.video, VIDEO_BASE_WIDTH, PICTURE_BASE_WIDTH)
        PlaceWhenReady(placement.entryid, positions[i], scale, shared)
    end
end

--- Shows the Add Image / Add Video dialog for files dropped on the table at
--- (mx, my), in the table's units. options.shared: start with "Share with
--- players" ticked (the files were dropped with Ctrl held); behindScreen:
--- dropped behind the Director's Screen, so they stay private and the
--- dialog does not offer to share them.
--- @param paths string[] local image and video files
--- @param mx number
--- @param my number
--- @param options nil|{shared: nil|boolean, behindScreen: nil|boolean}
function TableDropDialog.Show(paths, mx, my, options)
    options = options or {}
    local files = ReadFiles(paths)
    if #files == 0 then
        return
    end
    local dropped = #paths

    --the first picture's grid detection: done already if it was dropped before.
    local detectPath = nil
    if not files[1].video and MapGridDetection.CanDetect(files[1].path) then
        detectPath = files[1].path
    end
    local detection = nil
    if detectPath ~= nil then
        detection = MapGridDetection.Result(detectPath)
    end

    local state = {
        detection = detection,
        detecting = detectPath ~= nil and detection == nil,
        analysis = Analyse(files, detection),
        selected = nil,
        --the Director picked an option or changed the video settings: what
        --arrives later (a video's size) no longer changes them.
        picked = false,
        videoSet = false,
        videoDefaulted = false,
        loop = true,
        audio = false,
        shared = options.shared == true,
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
        local grid = a.grid
        if grid ~= nil and grid.source == "fit" then
            local agrees = cond(grid.confirmed, " The grid drawn on it lines up too.", "")
            if single then
                mapCallout = {
                    bold = string.format("This looks like a <nobr>%d x %d</nobr> map.", grid.tilesW, grid.tilesH),
                    text = "At 140 pixels per square it fits the grid exactly, the size map creators most often use." .. agrees,
                }
            else
                mapCallout = {
                    bold = string.format("These look like <nobr>%d x %d</nobr> maps.", grid.tilesW, grid.tilesH),
                    text = string.format("All %d are <nobr>%d x %d</nobr> pixels: exactly 140 pixels per square, the size map creators most often use.",
                        n, first.width, first.height) .. agrees,
                }
            end
        elseif grid ~= nil then
            local words = MapGridDetection.Describe(grid, first.width, first.height)
            mapCallout = {
                bold = cond(grid.hex, "Hex grid detected.", "Grid detected."),
                text = cond(single, words.text, "On the first of them: " .. words.text),
            }
        end

        if single then
            local mapText = "A playable map with a grid, tokens and fog of war. You'll set the grid size next."
            if grid ~= nil and grid.source == "fit" then
                mapText = "A playable map with a grid, tokens and fog of war. Its window opens showing the whole map."
            elseif grid ~= nil then
                mapText = "A playable map with a grid, tokens and fog of war. You'll check the grid we found next."
            end
            list[#list+1] = {
                id = "map",
                icon = "phosphor/map-trifold.png",
                title = "Map",
                text = mapText,
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
        local grid = state.analysis.grid
        --hex grids are previewed in the import wizard, which can draw them.
        if withGrid and grid ~= nil and not grid.hex and file.width > 0 then
            --the lines in image pixels: a fit's start at the image's edge, a
            --detected grid's where the detector found them.
            local cellW, cellH, x0, y0 = grid.cellW, grid.cellH, 0, 0
            if grid.source == "detected" then
                local d = grid.detection --[[@as ImageGridDetection]]
                x0 = d.originX % cellW
                y0 = d.originY % cellH
            end
            local scale = w / file.width
            --a line per square when they are big enough to see, else every few.
            local step = math.max(1, math.ceil(4 / math.max(0.01, cellW * scale)))
            local lines = {}
            local i = 0
            while x0 + i * cellW < file.width do
                local x = math.floor((x0 + i * cellW) * scale)
                if i % step == 0 and x > 0 and x < w then
                    lines[#lines+1] = gui.Panel{
                        floating = true,
                        halign = "left",
                        valign = "top",
                        x = x,
                        y = 0,
                        width = 1,
                        height = h,
                        bgimage = "panels/square.png",
                        bgcolor = "#00000066",
                        interactable = false,
                    }
                end
                i = i + 1
            end
            i = 0
            while y0 + i * cellH < file.height do
                local y = math.floor((y0 + i * cellH) * h / file.height)
                if i % step == 0 and y > 0 and y < h then
                    lines[#lines+1] = gui.Panel{
                        floating = true,
                        halign = "left",
                        valign = "top",
                        x = 0,
                        y = y,
                        width = w,
                        height = 1,
                        bgimage = "panels/square.png",
                        bgcolor = "#00000066",
                        interactable = false,
                    }
                end
                i = i + 1
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
        if single and state.analysis.grid ~= nil then
            mapLine = MapGridDetection.Describe(state.analysis.grid, first.width, first.height).short
        end
        local lookingLine = nil
        if state.detecting and state.analysis.grid == nil then
            lookingLine = "Looking for a grid..."
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
            lookingLine and gui.Label{
                classes = {"tableDropMuted"},
                text = lookingLine,
                width = PREVIEW_SIZE,
                height = "auto",
                fontSize = 14,
                italics = true,
                tmargin = 2,
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
            state.analysis = Analyse(files, state.detection)
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
        local shared = state.shared
        if id == "map" then
            Tabletop.AddFilesAsMap({first.path}, mx, my, {aspect = aspect, shared = shared})
        elseif id == "floors" then
            Tabletop.AddFilesAsMap(paths, mx, my, {aspect = aspect, shared = shared})
        elseif id == "variations" then
            local rest = {}
            for i = 2, #paths do
                rest[#rest+1] = paths[i]
            end
            Tabletop.AddFilesAsMap({first.path}, mx, my, {aspect = aspect, variations = rest, shared = shared})
        elseif id == "scenes" then
            Tabletop.AddFilesAsScenes(paths, mx, my, {shared = shared})
        else
            AddToTable(files, mx, my, state.loop, state.audio, shared)
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
                    LoadPreview(file)
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
                (not options.behindScreen) and gui.Check{
                    text = "Share with players",
                    value = state.shared,
                    width = 240,
                    halign = "left",
                    tmargin = 14,
                    hover = gui.Tooltip("Opens it on the players' tables too. Hold Ctrl as you drop files to start with this ticked."),
                    change = function(element)
                        state.shared = element.value
                    end,
                } or nil,
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

    --the grid detector runs on a worker thread while the dialog is up; a grid
    --it finds makes Map the suggestion (unless the Director already chose).
    if state.detecting and detectPath ~= nil then
        MapGridDetection.Request(detectPath, function(result)
            state.detecting = false
            state.detection = result
            FilesChanged(true)
        end)
    end

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

----------------------------------------------------------------------
--The drag card: by the mouse while files from the desktop are over the
--table (Tabletop.lua's BeginTableFileDrag). It shows what the files are (a
--picture of the first, what the dialog will suggest, its size), what
--releasing does, and for the Director whether the drop is shared with the
--players (Ctrl). A dashed outline on the table shows where the suggestion
--would land. Every color is a theme token, so it follows the color scheme.

local CARD_WIDTH = 240
local CARD_THUMB_HEIGHT = 84
local CARD_ICON_HEIGHT = 56
local CARD_HPAD = 10

local function DragCardStyles()
    return {
        {
            selectors = {"tableDragCard"},
            bgcolor = "@bg",
            borderColor = "@accent",
            borderWidth = 2,
            cornerRadius = 6,
        },
        {
            selectors = {"tableDragThumb"},
            bgcolor = "@bgAlt",
        },
        {
            selectors = {"tableDragBack"},
            bgcolor = "@bgAlt",
            borderColor = "@borderSolid",
            borderWidth = 1,
            cornerRadius = 6,
        },
        {
            selectors = {"tableDragRule"},
            bgcolor = "@borderSolid",
        },
        {
            selectors = {"tableDragName"},
            color = "@fgStrong",
        },
        {
            selectors = {"tableDragMeta"},
            color = "@fgMuted",
        },
        {
            selectors = {"tableDragGlyph"},
            bgcolor = "@fgMuted",
        },
        {
            selectors = {"tableDragBadge"},
            bgcolor = "@bgInverse",
            cornerRadius = 3,
        },
        {
            selectors = {"tableDragBadgeText"},
            color = "@fgInverse",
        },
        {
            selectors = {"tableDragActionIcon"},
            bgcolor = "@accentHover",
        },
        {
            selectors = {"tableDragAction"},
            color = "@fgStrong",
        },
        {
            selectors = {"tableDragShareIcon"},
            bgcolor = "@fgMuted",
        },
        {
            selectors = {"tableDragShareIcon", "shared"},
            bgcolor = "@share",
        },
        {
            selectors = {"tableDragShare"},
            color = "@fgMuted",
        },
        {
            selectors = {"tableDragShare", "shared"},
            color = "@share",
        },
        {
            selectors = {"tableDragFootprint"},
            bgcolor = "clear",
            borderColor = "@accentHover",
            borderWidth = 2,
            borderStyle = "dashed",
            borderDash = 10,
            borderGap = 7,
            cornerRadius = 4,
        },
    }
end

--Screen pixels (top-left origin) to a hud layer's own units: the layers sit
--below the title bar and may be scaled (as RichItemLink's drop ghost does).
local function ScreenToHudLayer(layer, px, py)
    local screen = dmhub.screenDimensions
    local below = dmhub.screenDimensionsBelowTitlebar
    if below.y <= 0 then
        return px, py
    end
    local scale = layer.renderedHeight / below.y
    return px * scale, (py - (screen.y - below.y)) * scale
end

--Puts the card below and right of the pointer, clear of the drop target hit
--test, or on the other side where that would run off the layer.
--- @param card Panel
--- @param layer Panel
local function PlaceCard(card, layer)
    local mouse = dmhub.mouseScreenPosition
    local x, y = ScreenToHudLayer(layer, mouse.x + 18, mouse.y + 22)
    if x + card.renderedWidth > layer.renderedWidth then
        x = ScreenToHudLayer(layer, mouse.x - 18, mouse.y) - card.renderedWidth
    end
    if y + card.renderedHeight > layer.renderedHeight then
        local _, above = ScreenToHudLayer(layer, mouse.x, mouse.y - 12)
        y = above - card.renderedHeight
    end
    card.x = math.max(0, x)
    card.y = math.max(0, y)
end

--The part of a picture that fills a w x h box, cropped to its centre (nil
--draws all of it, for a file of unknown size).
--- @param file TableDropFile
local function CoverRect(file, w, h)
    if file.width <= 0 or file.height <= 0 then
        return nil
    end
    local imageAspect = file.width / file.height
    local boxAspect = w / h
    if imageAspect > boxAspect then
        local f = boxAspect / imageAspect
        return {x1 = (1 - f) / 2, y1 = 0, x2 = (1 + f) / 2, y2 = 1}
    end
    local f = imageAspect / boxAspect
    return {x1 = 0, y1 = (1 - f) / 2, x2 = 1, y2 = (1 + f) / 2}
end

--"1 sound" / "3 sounds".
local function Count(n, one, many)
    return string.format("%d %s", n, cond(n == 1, one, many))
end

--The badge on the card's picture: what the dialog will suggest.
--- @param files TableDropFile[]
--- @param analysis TableDropAnalysis
local function SuggestionWord(files, analysis)
    local s = analysis.suggestion
    if s == "map" or s == "floors" or s == "variations" then
        return "Map"
    elseif s == "scenes" then
        return cond(#files == 1, "Scene", "Scenes")
    end
    return KindWord(#files, analysis.videos, #files == 1)
end

--The line under the name: the picture's size and the map's squares, or the
--names of several files.
--- @param files TableDropFile[]
--- @param analysis TableDropAnalysis
local function MediaMeta(files, analysis)
    local first = files[1]
    if #files == 1 then
        local parts = {}
        if first.width > 0 then
            parts[#parts+1] = string.format("%d x %d px", first.width, first.height)
        elseif first.video then
            parts[#parts+1] = "Video"
        end
        local grid = analysis.grid
        if grid ~= nil and analysis.suggestion == "map" then
            parts[#parts+1] = string.format("%d x %d %s", grid.tilesW, grid.tilesH, cond(grid.hex, "hexes", "squares"))
        end
        return table.concat(parts, "  -  ")
    end
    local names = {}
    for i, file in ipairs(files) do
        if i > 2 then
            names[#names+1] = string.format("+%d more", #files - 2)
            break
        end
        names[#names+1] = file.name
    end
    return table.concat(names, ", ")
end

--Where the dialog's suggestion would land for a drop at (mx, my), in the
--table's units: one rect per window or item, placed as Commit places them.
--- @param files TableDropFile[]
--- @param analysis TableDropAnalysis
--- @param mx number
--- @param my number
--- @return {x: number, y: number, w: number, h: number}[]
local function FootprintRects(files, analysis, mx, my)
    local area = Tabletop.LayerRect()
    local function Centred(w, h, cx, cy)
        return {
            x = math.max(0, math.min(math.floor(cx - w / 2), area.w - w)),
            y = math.max(0, math.min(math.floor(cy - h / 2), area.h - h)),
            w = w,
            h = h,
        }
    end
    local rects = {}
    local s = analysis.suggestion
    local first = files[1]
    if s == "map" or s == "floors" or s == "variations" then
        if first.width > 0 and first.height > 0 then
            local boxW, boxH = Tabletop.ShapedBox()
            local w, h = Tabletop.ShapeWindow(boxW, boxH, first.width / first.height)
            rects[1] = Centred(w, h, mx, my)
        end
    elseif s == "scenes" then
        local w, h = Tabletop.SceneWindowSize()
        for i = 1, #files do
            local step = 28 * (i - 1)
            rects[i] = Centred(w, h, mx + step, my + step)
        end
    else
        local sizes = LayoutSizes(files)
        local positions = GridPositions(sizes, mx, my)
        for i, size in ipairs(sizes) do
            rects[i] = {x = positions[i].x - size.w / 2, y = positions[i].y - size.h / 2, w = size.w, h = size.h}
        end
    end
    return rects
end

--- Whether files dropped on the table at the mouse now would be shared with
--- the players: "shared" (Ctrl held), "private", or "screen" (over the
--- Director's Screen, where a drop always stays private).
--- @return string
function TableDropDialog.DropShareState()
    local edge = DirectorScreen.EdgeX()
    if edge ~= nil then
        local mouse = dmhub.mouseScreenPosition
        local x = Tabletop.ScreenToTable(mouse.x, mouse.y)
        if x >= edge then
            return "screen"
        end
    end
    if dmhub.modKeys.ctrl then
        return "shared"
    end
    return "private"
end

--- Shows the card by the mouse while files from the desktop are over the
--- table, with the outline of where they would land. Both go when isActive
--- returns false or the card is destroyed.
--- args: paths, the files over the table; canShare, the Director (the card
--- says whether the drop is shared); isActive.
--- @param args {paths: string[], canShare: boolean, isActive: fun(): boolean}
--- @return nil|Panel
function TableDropDialog.ShowDragCard(args)
    local hud = GameHud.instance --[[@as GameHud]]
    if hud == nil then
        return nil
    end
    --the banner layer sits above every window; the outline goes on the
    --table among the windows.
    local layer = hud.bannerLayer
    if layer == nil or not layer.valid then
        layer = hud.documentsPanel
    end
    local tableLayer = hud.documentsPanel
    if layer == nil or not layer.valid then
        return nil
    end

    local mediaPaths = {}
    local sounds = {}
    local documents = {}
    local mapFiles = {}
    for _, path in ipairs(args.paths) do
        if FileDrops.IsAudio(path) then
            sounds[#sounds+1] = path
        elseif FileDrops.IsDocument(path) then
            documents[#documents+1] = path
        elseif FileDrops.IsMapFile(path) then
            mapFiles[#mapFiles+1] = path
        else
            mediaPaths[#mediaPaths+1] = path
        end
    end
    --Universal VTT files open the map import wizard instead of this dialog
    --(Tabletop's TableFilesDropped), so pictures dropped with them are not added.
    local skippedMedia = 0
    if #mapFiles > 0 then
        skippedMedia = #mediaPaths
        mediaPaths = {}
    end
    local files = ReadFiles(mediaPaths)
    local first = files[1]

    --the grid detector starts now, so the dialog has its answer on release.
    local detectPath = nil
    if first ~= nil and not first.video and MapGridDetection.CanDetect(first.path) then
        detectPath = first.path
    end
    --- @type nil|TableDropAnalysis
    local analysis = nil
    local function Reanalyse()
        if first ~= nil then
            local detection = nil
            if detectPath ~= nil then
                detection = MapGridDetection.Result(detectPath)
            end
            analysis = Analyse(files, detection)
        end
    end
    Reanalyse()

    local thumbHeight = cond(first ~= nil, CARD_THUMB_HEIGHT, CARD_ICON_HEIGHT)
    local innerW = CARD_WIDTH - 4
    local textW = CARD_WIDTH - CARD_HPAD * 2 - 4

    --the picture strip: the first file's picture (once read), else a glyph.
    local glyph
    if first ~= nil then
        glyph = cond(first.video, "phosphor/film-strip.png", "phosphor/image.png")
    elseif #mapFiles > 0 then
        glyph = "phosphor/map-trifold.png"
    elseif #documents > 0 then
        glyph = cond(FileDrops.Extension(documents[1]) == ".pdf", "phosphor/file-pdf.png", "phosphor/file-text.png")
    else
        glyph = "phosphor/waveform.png"
    end
    local picture = gui.Panel{
        classes = {"tableDragGlyph"},
        bgimage = glyph,
        width = 30,
        height = 30,
        halign = "center",
        valign = "center",
    }

    local badgeText = gui.Label{
        classes = {"tableDragBadgeText"},
        width = "auto",
        height = "auto",
        fontSize = 12,
        bold = true,
    }
    local badge = gui.Panel{
        classes = {"tableDragBadge"},
        bgimage = "panels/square.png",
        floating = true,
        halign = "right",
        valign = "top",
        x = -6,
        y = 6,
        width = "auto",
        height = "auto",
        hpad = 6,
        vpad = 1,
        borderBox = true,
        badgeText,
    }

    local nameLabel = gui.Label{
        classes = {"tableDragName"},
        width = textW,
        height = "auto",
        fontSize = 16,
        textWrap = true,
    }
    local metaLabel = gui.Label{
        classes = {"tableDragMeta"},
        width = textW,
        height = "auto",
        fontSize = 13,
        textWrap = true,
        tmargin = 2,
    }

    --what else the drop brings, beside the files shown.
    local extras = {}
    if (first ~= nil or #mapFiles > 0) and #documents > 0 then
        extras[#extras+1] = "+ " .. Count(#documents, "document", "documents") .. " for the journal"
    end
    if (first ~= nil or #documents > 0 or #mapFiles > 0) and #sounds > 0 then
        extras[#extras+1] = "+ " .. Count(#sounds, "sound", "sounds") .. " to play"
    end
    if skippedMedia > 0 then
        extras[#extras+1] = Count(skippedMedia, "picture", "pictures") .. " not added: drop separately"
    end
    local extrasLabel = nil
    if #extras > 0 then
        extrasLabel = gui.Label{
            classes = {"tableDragMeta"},
            text = table.concat(extras, "\n"),
            width = textW,
            height = "auto",
            fontSize = 13,
            tmargin = 2,
        }
    end

    local actionText
    if first ~= nil then
        actionText = cond(#files == 1, "Release to choose how to add it", "Release to choose how to add them")
    elseif #mapFiles > 0 then
        actionText = "Release to import as a map"
    elseif #documents > 0 then
        actionText = "Release to add to the journal and table"
    else
        actionText = cond(#sounds == 1, "Release to put it on the table to play", "Release to put them on the table to play")
    end

    --An icon and a line of text: what releasing does, and the share line.
    local function Row(iconClass, icon, labelClass, text)
        local iconPanel = gui.Panel{
            classes = {iconClass},
            bgimage = icon,
            width = 14,
            height = 14,
            valign = "center",
            rmargin = 6,
        }
        local label = gui.Label{
            classes = {labelClass},
            text = text,
            width = textW - 20,
            height = "auto",
            fontSize = 13,
            valign = "center",
        }
        local row = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            tmargin = 6,
            iconPanel,
            label,
        }
        return row, iconPanel, label
    end

    local actionRow = Row("tableDragActionIcon", "phosphor/download-simple.png", "tableDragAction", actionText)

    --the Director's share line, for files that make shareable items (sounds
    --on the table play for everyone and have no share).
    local shareRow, shareIcon, shareLabel = nil, nil, nil
    local shareState = nil
    if args.canShare and (first ~= nil or #documents > 0 or #mapFiles > 0) then
        shareRow, shareIcon, shareLabel = Row("tableDragShareIcon", "phosphor/share-network.png", "tableDragShare", "")
        shareRow.selfStyle.tmargin = 4
    end
    local function RefreshShare()
        if shareRow == nil or shareIcon == nil or shareLabel == nil then
            return
        end
        local state = TableDropDialog.DropShareState()
        if state == shareState then
            return
        end
        shareState = state
        shareIcon:SetClass("shared", state == "shared")
        shareLabel:SetClass("shared", state == "shared")
        if state == "screen" then
            shareIcon.bgimage = "phosphor/eye-slash.png"
            shareLabel.text = "Behind your screen: hidden from players"
        elseif state == "shared" then
            shareIcon.bgimage = "phosphor/share-network.png"
            shareLabel.text = "Share with players"
        else
            shareIcon.bgimage = "phosphor/share-network.png"
            shareLabel.text = "Hold Ctrl to share with players"
        end
    end

    --the outline on the table: one dashed rect per window or item.
    --- @type Panel[]
    local footprints = {}
    local function ClearFootprints()
        for _, panel in ipairs(footprints) do
            if panel.valid then
                panel:DestroySelf()
            end
        end
        footprints = {}
    end
    local function PlaceFootprints()
        if first == nil or analysis == nil or tableLayer == nil or not tableLayer.valid then
            return
        end
        local mouse = dmhub.mouseScreenPosition
        local mx, my = Tabletop.ScreenToTable(mouse.x, mouse.y)
        local rects = FootprintRects(files, analysis, mx, my)
        if #rects ~= #footprints then
            ClearFootprints()
            for _ = 1, #rects do
                local panel = gui.Panel{
                    classes = {"tableDragFootprint"},
                    styles = ThemeEngine.MergeTokens(DragCardStyles()),
                    bgimage = "panels/square.png",
                    floating = true,
                    halign = "left",
                    valign = "top",
                }
                tableLayer:AddChild(panel)
                panel:MakeNonInteractiveRecursive()
                panel:SetAsLastSibling()
                footprints[#footprints+1] = panel
            end
        end
        for i, rect in ipairs(rects) do
            local panel = footprints[i]
            panel.x = rect.x
            panel.y = rect.y
            panel.selfStyle.width = rect.w
            panel.selfStyle.height = rect.h
        end
    end

    local function RefreshFiles()
        if first ~= nil and analysis ~= nil then
            badgeText.text = SuggestionWord(files, analysis)
            nameLabel.text = cond(#files == 1, first.name,
                string.format("%d %s", #files, string.lower(KindWord(#files, analysis.videos, false))))
            metaLabel.text = MediaMeta(files, analysis)
        elseif #mapFiles > 0 then
            --the map is named after the first file; each file is a floor.
            badgeText.text = "Map"
            nameLabel.text = FileDrops.BaseName(mapFiles[1])
            metaLabel.text = cond(#mapFiles == 1, "New map with its walls, doors and lights",
                string.format("New map of %d floors, with walls, doors and lights", #mapFiles))
        elseif #documents > 0 then
            badgeText.text = cond(#documents == 1, string.upper(string.sub(FileDrops.Extension(documents[1]), 2)), "Documents")
            nameLabel.text = cond(#documents == 1, FileDrops.BaseName(documents[1]), Count(#documents, "document", "documents"))
            metaLabel.text = cond(dmhub.isDM, "Into your private documents", "Into My Private Documents")
        else
            badgeText.text = cond(#sounds == 1, "Sound", "Sounds")
            nameLabel.text = cond(#sounds == 1, FileDrops.BaseName(sounds[1]), Count(#sounds, "sound", "sounds"))
            metaLabel.text = "Played on the table"
        end
    end

    --several pictures: the next two fanned out behind the first.
    local backs = {}
    if #files > 1 then
        for i, angle in ipairs({6, -4}) do
            backs[#backs+1] = gui.Panel{
                classes = {"tableDragBack"},
                bgimage = "panels/square.png",
                floating = true,
                halign = "left",
                valign = "top",
                x = 4 * (3 - i),
                y = 4 * (3 - i) - 4,
                width = CARD_WIDTH,
                height = thumbHeight,
                rotate = angle,
            }
        end
    end
    local countBadge = nil
    if #files > 1 then
        countBadge = gui.Panel{
            classes = {"tableDragBadge"},
            bgimage = "panels/square.png",
            floating = true,
            halign = "left",
            valign = "top",
            x = 6,
            y = 6,
            width = "auto",
            height = "auto",
            hpad = 6,
            vpad = 1,
            borderBox = true,
            gui.Label{
                classes = {"tableDragBadgeText"},
                text = tostring(#files),
                width = "auto",
                height = "auto",
                fontSize = 12,
                bold = true,
            },
        }
    end

    local thumb = gui.Panel{
        classes = {"tableDragThumb"},
        bgimage = "panels/square.png",
        width = innerW,
        height = thumbHeight,
        flow = "none",
        picture,
        badge,
        countBadge,
    }

    local children = {}
    for _, back in ipairs(backs) do
        children[#children+1] = back
    end
    children[#children+1] = gui.Panel{
        classes = {"tableDragCard"},
        bgimage = "panels/square.png",
        width = CARD_WIDTH,
        height = "auto",
        flow = "vertical",
        pad = 2,
        borderBox = true,
        thumb,
        gui.Panel{
            classes = {"tableDragRule"},
            bgimage = "panels/square.png",
            width = innerW,
            height = 1,
        },
        gui.Panel{
            width = innerW,
            height = "auto",
            flow = "vertical",
            hpad = CARD_HPAD - 2,
            tpad = 7,
            bpad = 8,
            borderBox = true,
            nameLabel,
            metaLabel,
            extrasLabel,
            gui.Panel{
                classes = {"tableDragRule"},
                bgimage = "panels/square.png",
                width = "100%",
                height = 1,
                tmargin = 8,
            },
            actionRow,
            shareRow,
        },
    }

    --the picture is decoded a few frames in, so the card shows at once
    --(nil once done).
    --- @type nil|integer
    local previewIn = 2
    local detectionChanged = false
    local card = gui.Panel{
        styles = ThemeEngine.MergeTokens(DragCardStyles()),
        halign = "left",
        valign = "top",
        width = CARD_WIDTH + 8,
        height = "auto",
        flow = "vertical",
        children = children,

        thinkTime = 0.02,
        think = function(element)
            if mod.unloaded or not args.isActive() then
                if element.valid then
                    element:DestroySelf()
                end
                return
            end
            PlaceCard(element, layer)

            if first ~= nil and previewIn ~= nil then
                previewIn = previewIn - 1
                if previewIn <= 0 then
                    previewIn = nil
                    LoadPreview(first)
                    if first.preview ~= nil then
                        picture:SetClass("tableDragGlyph", false)
                        picture.bgimage = first.preview
                        picture.selfStyle.bgcolor = "white"
                        picture.selfStyle.width = innerW
                        picture.selfStyle.height = thumbHeight
                        picture.selfStyle.imageRect = CoverRect(first, innerW, thumbHeight)
                    end
                end
            end
            if detectionChanged then
                detectionChanged = false
                Reanalyse()
                RefreshFiles()
            end
            RefreshShare()
            PlaceFootprints()
        end,
        destroy = function(element)
            ClearFootprints()
        end,
    }
    RefreshFiles()
    RefreshShare()

    layer:AddChild(card)
    card:MakeNonInteractiveRecursive()
    card:SetAsLastSibling()
    PlaceCard(card, layer)
    PlaceFootprints()

    if detectPath ~= nil and MapGridDetection.Result(detectPath) == nil then
        MapGridDetection.Request(detectPath, function(result)
            detectionChanged = true
        end)
    end
    return card
end
