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

--- GetFormFields: Enumerates every form field widget (AcroForm) in the document. The callback receives an array with one entry per widget: name is the field name, page is the 0-based page index, value is the field's current value, exportValue is the checkbox/radio 'on' state name, and rect is the widget rectangle in page space. Called with nil if the document could not be read.
--- @param callback fun(fields: {name: string, type: 'text'|'checkbox'|'radio'|'combo'|'listbox'|'button'|'other', page: number, value: string, exportValue: string, checked: boolean, rect: {x1: number, y1: number, x2: number, y2: number}}[]|nil)
function PDFDocument:GetFormFields(callback)
	-- dummy implementation for documentation purposes only
end

--- FillForm: Fills the document's form fields (AcroForm) by name and delivers the resulting PDF as bytes; the source document is not modified. fields maps field names to values: strings/numbers fill text fields, booleans check or uncheck checkboxes and radio buttons. Fields not present in the table are left untouched; names that do not match any field are ignored with a logged warning. If flatten is true the filled values are baked into the page content and the output is no longer editable. The callback receives a LuaByteArray on success, or nil and an error message on failure.
--- @param options {fields: table<string, string|number|boolean>, flatten: nil|boolean, callback: fun(bytes: LuaByteArray|nil, error: nil|string)}
function PDFDocument:FillForm(options)
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
