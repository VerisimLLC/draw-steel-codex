--- @class TokenAnimationCompletionLua 
TokenAnimationCompletionLua = {}

--- Complete: Called by the Lua animation wrapper when the user's animation function returns. Engine-internal -- mod authors should never call this.
--- @return nil
function TokenAnimationCompletionLua:Complete()
	-- dummy implementation for documentation purposes only
end

--- CompleteWithError: Called by the Lua animation wrapper if the user's animation function threw. Engine-internal.
--- @param err string
function TokenAnimationCompletionLua:CompleteWithError(err)
	-- dummy implementation for documentation purposes only
end
