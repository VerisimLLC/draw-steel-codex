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
PDFDocumentAssetLua = {}

--- HaveReadPermissions
--- @return any
function PDFDocumentAssetLua:HaveReadPermissions() end

--- HaveEditPermissions
--- @return boolean
function PDFDocumentAssetLua:HaveEditPermissions() end

--- Upload
function PDFDocumentAssetLua:Upload() end
