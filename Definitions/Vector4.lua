--- @class Vector4 Represents a 4D vector with x, y, z, w components. Also used as a rectangle with x1, y1, x2, y2 accessors.
--- @field tostring string String representation of this vector.
--- @field Item number Access vector components by index (0=x, 1=y, 2=z, 3=w).
--- @field x number The x component (index 0).
--- @field y number The y component (index 1).
--- @field z number The z component (index 2).
--- @field w number The w component (index 3).
--- @field x1 number Rectangle alias: the first x coordinate (index 0).
--- @field y1 number Rectangle alias: the first y coordinate (index 1).
--- @field x2 number Rectangle alias: the second x coordinate (index 2).
--- @field y2 number Rectangle alias: the second y coordinate (index 3).
--- @field width number Rectangle width (x2 - x1).
--- @field height number Rectangle height (y2 - y1).
Vector4 = {}

--- DeepCopy
--- @return any
function Vector4:DeepCopy()
	-- dummy implementation for documentation purposes only
end

--- Deserialize
--- @param dict any
--- @return nil
function Vector4:Deserialize(dict)
	-- dummy implementation for documentation purposes only
end

--- Equals
--- @param other any
--- @return boolean
function Vector4:Equals(other)
	-- dummy implementation for documentation purposes only
end
