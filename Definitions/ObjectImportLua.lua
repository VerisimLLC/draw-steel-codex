---@meta

--- @class ObjectImportLua
--- @field outputEvent any
--- @field percentComplete any
--- @field sheets any
--- @field sizeInfo any
--- @field numErrors number
--- @field numSuccesses number
ObjectImportLua = {}

--- BeginImportFromImages
--- @param imageIds? string[]
--- @param threshold? number
--- @param breakupObjects? boolean
function ObjectImportLua:BeginImportFromImages(imageIds, threshold, breakupObjects) end

--- Destroy
function ObjectImportLua:Destroy() end

--- Upload
--- @param options? any
function ObjectImportLua:Upload(options) end
