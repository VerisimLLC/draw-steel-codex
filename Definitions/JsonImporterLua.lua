---@meta

--- @class JsonImporterLua
--- @field rows string[][]
JsonImporterLua = {}

--- Get
--- @param id? string
--- @return any
function JsonImporterLua:Get(id) end

--- WriteRow
--- @param row? any
function JsonImporterLua:WriteRow(row) end

--- WriteOutput
function JsonImporterLua:WriteOutput() end
