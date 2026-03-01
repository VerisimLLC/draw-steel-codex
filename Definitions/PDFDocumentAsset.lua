--- @class PDFDocumentAsset:GameAsset Base class for all game assets (images, audio, etc.) stored in the cloud asset system.
--- @field hasBookmarks boolean 
--- @field cachePath string 
PDFDocumentAsset = {}

--- SetBookmarks
--- @param toc any
--- @param parentGuid string?
--- @param level number?
--- @return nil
function PDFDocumentAsset:SetBookmarks(toc, parentGuid, level)
	-- dummy implementation for documentation purposes only
end

--- Sync
--- @return boolean
function PDFDocumentAsset:Sync()
	-- dummy implementation for documentation purposes only
end
