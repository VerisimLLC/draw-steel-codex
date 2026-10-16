---@meta

--- @class PDFDocumentAssetLua
--- @field nodeType string
--- @field parentFolder string
--- @field bookmarks table<string,PDFBookmark>
--- @field description any
--- @field ownerid string
--- @field ord number
--- @field canView any
--- @field hiddenFromPlayers any
--- @field hidden any
--- @field doc PDFDocument
--- @field id string
PDFDocumentAssetLua = {}

--- Opens a system save dialog and copies this PDF to the chosen path, downloading it first if this machine does not have it yet. options.filename is the default filename (defaults to the description plus .pdf). options.callback is called with the saved path, or nil if the user canceled or the copy failed.
--- @param options nil|{filename: nil|string, callback: nil|fun(path: nil|string)}
function PDFDocumentAssetLua:SaveToDisk(options) end

--- HaveReadPermissions
--- @return any
function PDFDocumentAssetLua:HaveReadPermissions() end

--- HaveEditPermissions
--- @return boolean
function PDFDocumentAssetLua:HaveEditPermissions() end

--- Upload
function PDFDocumentAssetLua:Upload() end
