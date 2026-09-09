---@meta

--- Represents a 3D vector with x, y, and z components.
--- @class Vector3
--- @field tostring string String representation of this vector.
--- @field Item number Access vector components by index (0=x, 1=y, 2=z).
--- @field x number The x component.
--- @field y number The y component.
--- @field z number The z component.
Vector3 = {}

--- DeepCopy
--- @return any
function Vector3:DeepCopy() end

--- Deserialize
--- @param dict? any
function Vector3:Deserialize(dict) end

--- Equals
--- @param other? any
--- @return boolean
function Vector3:Equals(other) end
