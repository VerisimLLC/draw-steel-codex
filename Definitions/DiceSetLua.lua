--- @class DiceSetLua Represents a set of dice with a specific model, color, and optional variables.
--- @field id string The unique identifier of this dice set.
--- @field model string The 3D model name used to render this dice set.
--- @field color string The color applied to this dice set as a hex color string.
--- @field vars table|nil Custom variables associated with this dice set.
DiceSetLua = {}

--- GetEffect: Returns the video effect with the given id, or nil if not found.
--- @param id string
--- @return any
function DiceSetLua.GetEffect(id)
	-- dummy implementation for documentation purposes only
end
