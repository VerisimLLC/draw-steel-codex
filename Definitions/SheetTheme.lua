---@meta

--- Base class for all game assets (images, audio, etc.) stored in the cloud asset system.
--- @class SheetTheme:GameAsset
--- @field id string
--- @field themeType string
--- @field sections table<string, any>
SheetTheme = {}

--- GetBaseTheme
--- @param themeType? string
--- @return SheetTheme
function SheetTheme.GetBaseTheme(themeType) end

--- GetActiveTheme
--- @param themeid? string
--- @param themeType? string
--- @return SheetTheme
function SheetTheme.GetActiveTheme(themeid, themeType) end

--- RegisterTheme
--- @param themeType? any
--- @param sectionid? any
--- @param styles? any
function SheetTheme.RegisterTheme(themeType, sectionid, styles) end
