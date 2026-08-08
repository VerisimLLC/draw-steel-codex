--- @class LuaCore Core utility functions for creating primitive Lua types such as Color, Loc, Vector2, Vector3, and Vector4.
LuaCore = {}

--- Color: Examples:
core.Color('#ff0000'): create a red color.
core.Color('#00ff00bb'): create a green color that is partly translucent.
core.Color{ r = 1, g = 0, b = 0 }: creates a red color.
core.Color{ h = 0.3, s = 0.8, v = 0.8 }: creates a color hue shifted 30%, saturation of 80%, and value of 80%.
core.Color{ h = 0, s = 0, v = 5 }: creates a super bright white.
--- @param value string|table
---  @return Color
function LuaCore.Color(value)
	-- dummy implementation for documentation purposes only
end

--- Loc: Creates a Loc which specifies a location on the map.
--- @param value { x: number, y: number, floorIndex?: number, tinyLoc?: number }
---  @return Loc
function LuaCore.Loc(value)
	-- dummy implementation for documentation purposes only
end

--- Vector2: Create a Vector2.
--- @param x number
--- @param y number
--- @return Vector2
function LuaCore.Vector2(x, y)
	-- dummy implementation for documentation purposes only
end

--- Vector3: Create a Vector3.
--- @param x number
--- @param y number
--- @param z number
--- @return Vector3
function LuaCore.Vector3(x, y, z)
	-- dummy implementation for documentation purposes only
end

--- Vector4: Create a Vector4.
--- @param x number
--- @param y number
--- @param z number
--- @param w number
--- @return Vector4
function LuaCore.Vector4(x, y, z, w)
	-- dummy implementation for documentation purposes only
end

--- PopulateTooltipAlignmentFromDirection: Will set the halign and valign keys in the output table based on the direction specified by 'dir'.
--- @param dir Vector2 A direction.
--- @param output A table to populate with halign and valign keys.
function LuaCore.PopulateTooltipAlignmentFromDirection(dir, output)
	-- dummy implementation for documentation purposes only
end
