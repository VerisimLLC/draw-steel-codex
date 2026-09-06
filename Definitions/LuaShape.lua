---@meta

--- Represents a shape on the map, such as a spell area of effect.
--- @class LuaShape
--- @field perimeter Vector2[] (Read-only) The perimeter of the shape as a list of Vector2 points.
--- @field xpos number (Read-only) The x position of the shape's center or origin in world coordinates.
--- @field ypos number (Read-only) The y position of the shape's center or origin in world coordinates.
--- @field valid boolean (Read-only) False if the shape has lost its stored description and covers nothing. A LuaShape serialized while its description was missing is written as data:"null" and comes back permanently broken -- it can never be positioned, filled or drawn. Check this before reading shape/radius/xpos/ypos or calling Mark/Clone/Grow on a shape that came from stored data, and replace the shape (dmhub.CalculateShape) if it is false.
--- @field shape SpellShapes (Read-only) The type of shape (e.g. 'Sphere', 'Cube', 'Cone'). nil if the shape is not valid.
--- @field radius number The radius of the shape in tiles. Reads as 0 and ignores writes if the shape is not valid.
--- @field origin Loc (Read-only) The origin location of the shape.
--- @field locations Loc[] The list of all locations contained within this shape. Can be set to override the shape's locations.
LuaShape = {}

--- Creates a deep copy of this shape.
--- @return LuaShape
function LuaShape:Clone() end

--- Returns a new shape that is expanded by the given number of tiles in all directions.
--- @return LuaShape
--- @param namount? number
function LuaShape:Grow(namount) end

--- Returns true if the given token occupies any location within this shape.
--- @param token? any
--- @return boolean
function LuaShape:ContainsToken(token) end

--- Mark this shape on the map, optionally attaching a standard aura label, and return a reference that you should call Destroy() on when you want to stop displaying it.
--- @param args {color: ColorArg, video: nil|string, showLocs: nil|boolean, label: nil|string}
--- @return LuaObjectReference
function LuaShape:Mark(args) end

--- Returns true if this shape contains exactly the same locations as the other shape.
--- @param other LuaShape
--- @return boolean
function LuaShape:Equal(other) end
