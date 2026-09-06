---@meta

--- @class TokenAnimationCompletionLua
TokenAnimationCompletionLua = {}

--- Called by the Lua animation wrapper when the user's animation function returns. Engine-internal -- mod authors should never call this.
function TokenAnimationCompletionLua:Complete() end

--- Called by the Lua animation wrapper if the user's animation function threw. Engine-internal.
--- @param err string
function TokenAnimationCompletionLua:CompleteWithError(err) end
