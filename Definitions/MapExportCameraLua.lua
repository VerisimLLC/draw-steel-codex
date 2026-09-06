---@meta

--- @class MapExportCameraLua
--- @field ppu any
--- @field width any
--- @field height any
--- @field previewDirectory any The directory the current game's map preview JPEGs are cached in.
MapExportCameraLua = {}

--- SetMapTourExport
--- @param options? any
function MapExportCameraLua:SetMapTourExport(options) end

--- SetFullMapExport
function MapExportCameraLua:SetFullMapExport() end

--- ExportVideo
--- @param options? any
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
