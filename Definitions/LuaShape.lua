--- @class LuaShape Represents a shape on the map, such as a spell area of effect.
--- @field perimeter Vector2[] (Read-only) The perimeter of the shape as a list of Vector2 points.
--- @field xpos number (Read-only) The x position of the shape's center or origin in world coordinates.
--- @field ypos number (Read-only) The y position of the shape's center or origin in world coordinates.
--- @field shape SpellShapes (Read-only) The type of shape (e.g. 'Sphere', 'Cube', 'Cone').
--- @field radius number The radius of the shape in tiles.
--- @field origin Loc (Read-only) The origin location of the shape.
--- @field locations Loc[] The list of all locations contained within this shape. Can be set to override the shape's locations.
LuaShape = {}

--- Clone: Creates a deep copy of this shape.
--- @return LuaShape
function LuaShape:Clone()
	-- dummy implementation for documentation purposes only
end

--- Grow: Returns a new shape that is expanded by the given number of tiles in all directions.
--- @return LuaShape
function LuaShape:Grow(namount)
	-- dummy implementation for documentation purposes only
end

--- ContainsToken: Returns true if the given token occupies any location within this shape.
--- @param token any
--- @return boolean
function LuaShape:ContainsToken(token)
	-- dummy implementation for documentation purposes only
end

--- Mark: Mark this shape on the map, returning a reference that you should call Destroy() on when you want to stop displaying it.
--- @param args {color: Color, video: nil|string, showLocs: nil|boolean}
--- @return LuaObjectReference
function LuaShape:Mark(args)
	-- dummy implementation for documentation purposes only
end

--- Equal: Returns true if this shape contains exactly the same locations as the other shape.
--- @param other LuaShape
--- @return boolean
function LuaShape:Equal(other)
	-- dummy implementation for documentation purposes only
end
