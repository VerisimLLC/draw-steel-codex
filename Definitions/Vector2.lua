---@meta

--- Represents a 2D vector with x and y components.
--- @class Vector2
--- @field tostring string String representation of this vector.
--- @field Item number Access vector components by index (0=x, 1=y).
--- @field x number The x component.
--- @field y number The y component.
--- @field length number The magnitude (length) of the vector.
--- @field unit Vector2 A normalized (unit length) copy of this vector.
--- @field angle number The signed angle in degrees from the up direction (0,1) to this vector.
Vector2 = {}

--- DeepCopy
--- @return any
function Vector2:DeepCopy() end

--- Deserialize
--- @param dict? any
function Vector2:Deserialize(dict) end

--- Equals
--- @param other? any
--- @return boolean
function Vector2:Equals(other) end

--- Returns this vector rotated by the given number of degrees.
--- @param degrees number
--- @return Vector2
function Vector2:Rotate(degrees) end
