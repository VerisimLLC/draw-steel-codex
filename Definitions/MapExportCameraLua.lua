---@meta

--- @class MapExportCameraLua
--- @field ppu any
--- @field width any
--- @field height any
--- @field previewDirectory any The directory the current game's map preview JPEGs are cached in.
MapExportCameraLua = {}

--- Switch the export to a map tour: a seamless looping video that sweeps the camera across the map and back, showing parallax, and fading out each floor from the top down to reveal the one beneath (fading them back in on the return). #MapExport shows the tour live. duration is the length of one full loop in seconds. bottomFloor (a floor id, not a layer id) stops the fades there: that floor and every floor beneath it stay drawn the whole time, e.g. a starfield floor under a map.
--- @param options {width: number|nil, height: number|nil, duration: number|nil, bottomFloor: string|nil}
function MapExportCameraLua:SetMapTourExport(options) end

--- SetFullMapExport
function MapExportCameraLua:SetFullMapExport() end

--- Record the current export (the full map, or the map tour set by SetMapTourExport) as an MP4. hz is the frame rate (default 60) and duration the length in seconds (default 50). progress(fraction) is called as frames are written and complete() when the video is done. Then the video is saved to path if one is given (an .mp4 file; its folder is created), otherwise a Save dialog asks where; error(message) is called if it cannot be saved.
--- @param options {hz: number|nil, duration: number|nil, path: string|nil, progress: (fun(fraction: number): nil)|nil, complete: (fun(): nil)|nil, error: (fun(message: string): nil)|nil}
function MapExportCameraLua:ExportVideo(options) end

--- CancelVideoExport
function MapExportCameraLua:CancelVideoExport() end

--- Render the current map -- every visible floor, lit, no tokens, no grid or selection overlay -- and save it as a JPEG in the local map-preview cache (see previewDirectory). The image is at most maxDimension pixels on its largest side (default 1024). Asynchronous: complete(path) is called with the saved file path, error(message) if the capture could not run. Only one capture runs at a time.
--- @param options {maxDimension: number|nil, quality: number|nil, complete: (fun(path: string): nil)|nil, error: (fun(message: string): nil)|nil}
function MapExportCameraLua:CapturePreview(options) end

--- Path of the cached preview JPEG for the given map id (current map if nil), or nil if no preview has been captured for it.
--- @param mapid string|nil
--- @return string|nil
function MapExportCameraLua:GetPreviewPath(mapid) end
