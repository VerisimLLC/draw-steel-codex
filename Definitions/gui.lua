--- @class gui Factory class for creating GUI elements such as panels, labels, inputs, and tables in the sheet system.
gui = {}

--- Style: Create a Style
--- @param args StyleArgs
--- @return Style
function gui.Style(args)
	-- dummy implementation for documentation purposes only
end

--- Panel: Create a Panel
--- @param args PanelArgs
--- @return Panel
function gui.Panel(args)
	-- dummy implementation for documentation purposes only
end

--- Carousel: Create a Carousel panel
--- @param args CarouselArgs
--- @return Carousel
function gui.Carousel(table)
	-- dummy implementation for documentation purposes only
end

--- MapImport: Create a MapImport panel for importing map files.
--- @param table table The map import configuration.
--- @return Panel
function gui.MapImport(table)
	-- dummy implementation for documentation purposes only
end

--- Table: Create a Table panel
--- @param args TablePanelArgs
--- @return TablePanel
function gui.Table(table)
	-- dummy implementation for documentation purposes only
end

--- TableRow: Create a Row panel
--- @param args RowPanelArgs
--- @return RowPanel
function gui.TableRow(table)
	-- dummy implementation for documentation purposes only
end

--- Label: Create a Label panel
--- @param args LabelArgs
--- @return Label
function gui.Label(table)
	-- dummy implementation for documentation purposes only
end

--- Input: Create a Input panel
--- @param args InputArgs
--- @return Input
function gui.Input(table)
	-- dummy implementation for documentation purposes only
end

--- RegisterTheme: Registers style overrides for a theme section.
--- @param themeid string The theme ID.
--- @param sectionid string The section within the theme.
--- @param styles table The style overrides to register.
function gui.RegisterTheme(themeid, sectionid, styles)
	-- dummy implementation for documentation purposes only
end

--- CreateTheme: Creates a new sheet theme with the given type and a generated GUID.
--- @param themeType string The theme type identifier.
--- @return LuaSheetTheme
function gui.CreateTheme(themeType)
	-- dummy implementation for documentation purposes only
end

--- Gradient: Creates a style gradient from the given configuration table.
--- @param value table The gradient configuration.
--- @return StyleGradientLua
function gui.Gradient(value)
	-- dummy implementation for documentation purposes only
end

--- MarkdownStyle: Creates a markdown style configuration from the given table.
--- @param value table The markdown style settings.
--- @return MarkdownStyle
function gui.MarkdownStyle(value)
	-- dummy implementation for documentation purposes only
end

--- TryGetImageDimensions: Tries to get the dimensions of an image by ID. Returns a table with width, height, and ppu fields, or nil if not available.
--- @param imageid string The image asset ID.
--- @return nil|table
function gui.TryGetImageDimensions(imageid)
	-- dummy implementation for documentation purposes only
end

--- GetImageDimensionsCallback: Asynchronously gets image dimensions and calls the callback with a table containing width, height, and ppu.
--- @param imageid string The image asset ID.
--- @param f function Callback receiving a table with width, height, and ppu.
function gui.GetImageDimensionsCallback(imageid, f)
	-- dummy implementation for documentation purposes only
end

--- GetSheetById: Finds a sheet panel by its ID across all top-level sheets. Returns nil if not found.
--- @param id string The panel ID.
--- @return nil|Panel
function gui.GetSheetById(id)
	-- dummy implementation for documentation purposes only
end
