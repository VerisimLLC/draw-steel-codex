---@meta

--- Factory class for creating GUI elements such as panels, labels, inputs, and tables in the sheet system.
--- @class gui
--- @field availableFonts string[] List of available font ids configured on GameConfig for the current white-label build. Each entry is a string id usable with gui.Style/gui.Label etc.
gui = {}

--- Create a Style
--- @param args StyleArgs
--- @return Style
function gui.Style(args) end

--- Create a Panel
--- @param args PanelArgs
--- @return Panel
function gui.Panel(args) end

--- Canvas
--- @deprecated
--- @param table? any
--- @return any
function gui.Canvas(table) end

--- Create a Carousel panel
--- @param args PanelArgs
--- @return LuaSheetCarousel
function gui.Carousel(args) end

--- Create a MapImport panel for importing map files.
--- @param table table The map import configuration.
--- @return Panel
function gui.MapImport(table) end

--- Create a Table panel
--- @param args PanelArgs
--- @return TablePanel
function gui.Table(args) end

--- Create a Row panel
--- @param args PanelArgs
--- @return RowPanel
function gui.TableRow(args) end

--- Create a Label panel
--- @param args LabelArgs
--- @return Label
function gui.Label(args) end

--- Checkbox
--- @deprecated
--- @param table? any
--- @return any
function gui.Checkbox(table) end

--- Dropdown
--- @deprecated
--- @param table? any
--- @return any
function gui.Dropdown(table) end

--- Create a Input panel
--- @param args InputArgs
--- @return Input
function gui.Input(args) end

--- Create a TextEditor panel: a multiline rich text editor (used by the journal). Backed by a fork of TMP_InputField with a working scrollbar, undo/redo, and find & replace.
--- @param args TextEditorArgs
--- @return TextEditor
function gui.TextEditor(args) end

--- Icon
--- @deprecated
--- @param table? any
--- @return any
function gui.Icon(table) end

--- Button
--- @deprecated
--- @param table? any
--- @return any
function gui.Button(table) end

--- MapPreview
--- @deprecated
--- @param table? any
--- @return any
function gui.MapPreview(table) end

--- Create a DicePreview panel: a cage that resting preview dice anchor to. Register it with SetAsDicePreviewPanel(true), seed dice with dmhub.Roll{preview = true, previewPanel = <panel>}, and route input through its DicePreview* methods.
--- @param args PanelArgs
--- @return DicePreview
function gui.DicePreview(args) end

--- Registers style overrides for a theme section.
--- @param themeid string The theme ID.
--- @param sectionid string The section within the theme.
--- @param styles table The style overrides to register.
function gui.RegisterTheme(themeid, sectionid, styles) end

--- Creates a new sheet theme with the given type and a generated GUID.
--- @param themeType string The theme type identifier.
--- @return LuaSheetTheme
function gui.CreateTheme(themeType) end

--- Creates a style gradient from the given configuration table.
--- @param value table The gradient configuration.
--- @return Gradient
function gui.Gradient(value) end

--- Creates a markdown style configuration from the given table.
--- @param value table The markdown style settings.
--- @return LuaMarkdownStyle
function gui.MarkdownStyle(value) end

--- Tries to get the dimensions of an image by ID. Returns a table with width, height, and ppu fields, or nil if not available.
--- @param imageid string The image asset ID.
--- @return nil|table
function gui.TryGetImageDimensions(imageid) end

--- Asynchronously gets image dimensions and calls the callback with a table containing width, height, and ppu.
--- @param imageid string The image asset ID.
--- @param f function Callback receiving a table with width, height, and ppu.
function gui.GetImageDimensionsCallback(imageid, f) end

--- Finds a sheet panel by its ID across all top-level sheets. Returns nil if not found.
--- @param id string The panel ID.
--- @return nil|Panel
function gui.GetSheetById(id) end

--- Diagnostic: returns a state-snapshot table for the panel with the given id, or nil if not found. Walks all top-level sheets. Useful for chasing UI regressions from the MCP bridge.
--- @param id string The panel id to look up.
--- @return nil|table
function gui.DebugDumpPanel(id) end

--- Diagnostic: enable/disable debugLogging on a panel by id. Per-panel diagnostics (DoUpdateMaterial sprite assignments, bgimage square fallback, etc.) only log when this flag is on for the panel. Returns true if found.
--- @param id string
--- @param on boolean
--- @return boolean
function gui.DebugSetLogging(id, on) end

--- Diagnostic: returns a flat array of every panel id reachable from any top-level sheet. Useful for finding ids to pass to DebugDumpPanel.
--- @return string[]
function gui.DebugListPanels() end
