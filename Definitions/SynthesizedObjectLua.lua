---@meta

--- Describes a single object type used in an effects brush synthesis, including its visual randomization parameters.
--- @class SynthesizedObjectLua
--- @field objectid string The asset ID of the object to synthesize.
--- @field weight number The relative weight of this object in the brush, controlling how frequently it appears.
--- @field scale number The base scale multiplier for this object.
--- @field randomScale number The amount of random scale variation applied to each instance.
--- @field randomRotation number The amount of random rotation variation in degrees applied to each instance.
--- @field randomHue number The amount of random hue shift applied to each instance.
--- @field randomSaturation number The amount of random saturation variation applied to each instance.
--- @field randomLuminance number The amount of random luminance variation applied to each instance.
--- @field zorder number The base z-order for rendering this object.
--- @field randomZorder number The amount of random z-order variation applied to each instance.
SynthesizedObjectLua = {}
