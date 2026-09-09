---@meta

--- Core utility functions for creating primitive Lua types such as Color, Loc, Vector2, Vector3, and Vector4.
--- @class core
core = {}

--- Examples:
--- core.Color('#ff0000'): create a red color.
--- core.Color('#00ff00bb'): create a green color that is partly translucent.
--- core.Color{ r = 1, g = 0, b = 0 }: creates a red color.
--- core.Color{ h = 0.3, s = 0.8, v = 0.8 }: creates a color hue shifted 30%, saturation of 80%, and value of 80%.
--- core.Color{ h = 0, s = 0, v = 5 }: creates a super bright white.
--- @param value string|table
--- @return Color
function core.Color(value) end

--- Creates a Loc which specifies a location on the map.
--- @param value { x: number, y: number, floorIndex?: number, tinyLoc?: number }
--- @return Loc
function core.Loc(value) end

--- Create a Vector2.
--- @param x number
--- @param y number
--- @return Vector2
function core.Vector2(x, y) end

--- Create a Vector3.
--- @param x number
--- @param y number
--- @param z number
--- @return Vector3
function core.Vector3(x, y, z) end

--- Create a Vector4.
--- @param x number
--- @param y number
--- @param z number
--- @param w number
--- @return Vector4
function core.Vector4(x, y, z, w) end

--- Create a Gradient object.
--- @deprecated
--- @param value Gradient
--- @return Gradient
function core.Gradient(value) end

--- Will set the halign and valign keys in the output table based on the direction specified by 'dir'.
--- @param dir Vector2Arg A direction.
--- @param output table A table to populate with halign and valign keys.
function core.PopulateTooltipAlignmentFromDirection(dir, output) end
