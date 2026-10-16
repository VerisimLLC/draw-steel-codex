local mod = dmhub.GetModLoading()

--Files dragged in from the operating system (Explorer, Finder). The engine
--hands them to the panel under the pointer that lists their extension in
--dragAndDropExtensions (chat, the journal, a journal document, the bare
--table, ...: each previews with dragfilesenter / dragfilesleave and acts in
--dropfiles). With no such panel, over the live map, the engine itself sets
--a token's avatar or places map objects, and calls
--dmhub.FileDragGameTarget (below) so we can preview that.
--These are the helpers those drop targets share.

--- @class FileDrops
FileDrops = {}

FileDrops.IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp"}
FileDrops.VIDEO_EXTENSIONS = {".mp4", ".webm"}

--- Images and videos: what the map, tokens, the table and the journal take.
FileDrops.MEDIA_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp", ".mp4", ".webm"}

--- Audio: what the soundboards and the table take (as the Studio's own upload,
--- which converts .flac and .m4a).
FileDrops.AUDIO_EXTENSIONS = {".ogg", ".mp3", ".wav", ".flac", ".m4a"}

--- True for an audio file (by extension).
--- @param path string
--- @return boolean
function FileDrops.IsAudio(path)
    local ext = FileDrops.Extension(path)
    for _, audioExt in ipairs(FileDrops.AUDIO_EXTENSIONS) do
        if ext == audioExt then
            return true
        end
    end
    return false
end

--- The file's extension, lower case with its dot (".png"), or "".
--- @param path string
--- @return string
function FileDrops.Extension(path)
    return string.lower(string.match(path, "(%.[^%.\\/]+)$") or "")
end

--- True for a video file (by extension).
--- @param path string
--- @return boolean
function FileDrops.IsVideo(path)
    local ext = FileDrops.Extension(path)
    for _, videoExt in ipairs(FileDrops.VIDEO_EXTENSIONS) do
        if ext == videoExt then
            return true
        end
    end
    return false
end

--- The file's name without its folder or extension ("forest" for
--- "C:\maps\forest.png").
--- @param path string
--- @return string
function FileDrops.BaseName(path)
    local filename = string.match(path, "([^/\\]+)$") or path
    return string.match(filename, "(.+)%.[^%.]+$") or filename
end

--- How a drop's files read in a sentence: the file's name, or "3 files".
--- @param paths string[]
--- @return string
function FileDrops.Describe(paths)
    if #paths == 1 then
        return FileDrops.BaseName(paths[1])
    end
    return string.format("%d files", #paths)
end

--- Uploads an image or video file as an image asset and returns its id at
--- once (the asset shows locally straight away and finishes uploading
--- later), or nil when the file can't be read. An upload error is reported
--- in a dialog unless options.error is given.
--- @param path string
--- @param options nil|{library: nil|string, imageType: nil|string, parentFolder: nil|string, upload: nil|fun(imageid: string), error: nil|fun(message: string)}
--- library: also add the asset to this image library (as its picker would).
--- @return nil|string
function FileDrops.UploadImage(path, options)
    options = options or {}
    local name = FileDrops.BaseName(path)
    return assets:UploadImageAsset{
        path = path,
        description = name,
        imageType = options.imageType,
        parentFolder = options.parentFolder,
        error = function(text)
            if options.error ~= nil then
                options.error(text)
                return
            end
            gui.ModalMessage{
                title = "Could not upload " .. name,
                message = text,
            }
        end,
        addlocal = function(imageid)
            if options.library ~= nil then
                dmhub.AddImageToLibraryLocally(options.library, imageid)
            end
        end,
        upload = function(imageid)
            if options.library ~= nil then
                dmhub.AddAndUploadImageToLibrary(options.library, imageid)
            end
            if options.upload ~= nil then
                options.upload(imageid)
            end
        end,
    }
end

--- Shows the card by the mouse that says what releasing the files will do
--- (the same card as items dragged onto a document). It follows the drag and
--- goes when isActive returns false, or when the caller destroys it.
--- @param text string
--- @param isActive fun(): boolean
--- @return nil|Panel
function FileDrops.ShowGhost(text, isActive)
    return RichItemLink.ShowDropGhost({}, function()
        return isActive()
    end, text)
end

--The card for a drag over the map (dmhub.FileDragGameTarget).
local g_mapGhost = nil

local function ClearMapGhost()
    if g_mapGhost ~= nil and g_mapGhost.valid then
        g_mapGhost:DestroySelf()
    end
    g_mapGhost = nil
end

--The engine's preview hook for files over the live map that no panel
--takes: onto a token you control (its avatar), or the map itself (objects,
--Director only). The token also lights up as if hovered, since the mouse
--follows the drag. nil when the drag leaves or drops.
dmhub.FileDragGameTarget = function(info)
    ClearMapGhost()
    if info == nil or mod.unloaded then
        return
    end

    local text
    if info.target == "token" then
        local name = nil
        if info.token ~= nil then
            name = info.token.name
        end
        if name ~= nil and name ~= "" then
            text = string.format("Set as %s's avatar", name)
        else
            text = "Set as this token's avatar"
        end
    elseif #info.paths == 1 then
        text = "Place on the map as an object"
    else
        text = string.format("Place %d objects on the map", #info.paths)
    end

    local ghost
    ghost = FileDrops.ShowGhost(text, function()
        return g_mapGhost == ghost
    end)
    g_mapGhost = ghost
end
