---@meta

--- Base class for all game assets (images, audio, etc.) stored in the cloud asset system.
--- @class PDFDocumentAsset:GameAsset
--- @field hasBookmarks boolean
--- @field cachePath string
--- @field imageId string
--- @field bookmarks table<string, PDFBookmark>
--- @field ownerid string
PDFDocumentAsset = {}

--- SetBookmarks
--- @param toc? any
--- @param parentGuid? string
--- @param level? number
function PDFDocumentAsset:SetBookmarks(toc, parentGuid, level) end

--- Sync
--- @return boolean
function PDFDocumentAsset:Sync() end
