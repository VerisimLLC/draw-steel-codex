---@meta

--- Configuration options controlling how effects brush synthesis generates and distributes objects.
--- @class EffectsBrushSynthesisOptionsLua
--- @field seed number The random seed used for deterministic brush generation.
--- @field numObjects number The total number of objects to generate in the brush.
--- @field spreadIterations number The number of iterations used to spread objects apart to reduce overlap.
--- @field spreadMult number The multiplier controlling how aggressively objects are pushed apart during spread iterations.
EffectsBrushSynthesisOptionsLua = {}
