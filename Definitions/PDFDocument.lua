--- @class PDFDocument 
--- @field summary PDFSummary 
PDFDocument = {}

--- TextInRect
--- @param npage number
--- @param left number
--- @param top number
--- @param right number
--- @param bottom number
--- @param callback any
--- @return nil
function PDFDocument:TextInRect(npage, left, top, right, bottom, callback)
	-- dummy implementation for documentation purposes only
end

--- TextLayout
--- @param npage number
--- @param callback any
--- @return nil
function PDFDocument:TextLayout(npage, callback)
	-- dummy implementation for documentation purposes only
end

--- Search
--- @param searchText string
--- @return {page: number, index: number}[]
function PDFDocument:Search(searchText)
	-- dummy implementation for documentation purposes only
end

--- RenderToData
--- @param npage number
--- @param width any
--- @param height any
--- @param region any
--- @param callback any
--- @return nil
function PDFDocument:RenderToData(npage, width, height, region, callback)
	-- dummy implementation for documentation purposes only
end

--- GetPageImageId
--- @param npage number
--- @return string
function PDFDocument:GetPageImageId(npage)
	-- dummy implementation for documentation purposes only
end

--- GetPageThumbnailId
--- @param npage number
--- @return string
function PDFDocument:GetPageThumbnailId(npage)
	-- dummy implementation for documentation purposes only
end
