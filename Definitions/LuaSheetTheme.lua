---@meta

--- @class LuaSheetTheme
--- @field editorSections any
--- @field description any
--- @field id any
--- @field themeType any
LuaSheetTheme = {}

--- Upload
function LuaSheetTheme:Upload() end

--- GetSection
--- @param id? string
--- @return any
function LuaSheetTheme:GetSection(id) end

--- SetSection
--- @param id? string
--- @param styles? any
function LuaSheetTheme:SetSection(id, styles) end
