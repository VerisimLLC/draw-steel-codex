--- @class Color Represents a color stored internally in HSVA (hue, saturation, value, alpha) format. Supports both RGB and HSV access.
--- @field tostring string Gets or sets the color as an HTML string (e.g. '#FF0000FF').
--- @field h number Shorthand for hue (0-1).
--- @field s number Shorthand for saturation (0-1).
--- @field v number Shorthand for value/brightness (0+, values >1 produce HDR).
--- @field r number Shorthand for the red channel (0-1).
--- @field g number Shorthand for the green channel (0-1).
--- @field b number Shorthand for the blue channel (0-1).
--- @field a number Shorthand for the alpha channel (0-1).
--- @field red number The red channel (0-1).
--- @field green number The green channel (0-1).
--- @field blue number The blue channel (0-1).
--- @field alpha number The alpha (opacity) channel (0-1).
--- @field hue number The hue component (0-1).
--- @field saturation number The saturation component (0-1).
--- @field value number The value/brightness component (0+, values >1 produce HDR).
Color = {}

--- Deserialize
--- @param dict any
--- @return nil
function Color:Deserialize(dict)
	-- dummy implementation for documentation purposes only
end

--- Equals
--- @param other any
--- @return boolean
function Color:Equals(other)
	-- dummy implementation for documentation purposes only
end

--- Modify: Returns a new Color with properties overridden by the given table values.
--- @param table table -- A table of Color property overrides.
--- @return Color
function Color:Modify(table)
	-- dummy implementation for documentation purposes only
end
