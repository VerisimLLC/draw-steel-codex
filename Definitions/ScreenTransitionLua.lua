--- @class ScreenTransitionLua Handle returned by dmhub.StartScreenTransition(). Holds a screen snapshot drawn over all other UI and dissolves it away using a mask + soft threshold (same effect as the titlescreen loading transition). Call CrossFade(alpha) each frame to control visibility (1 = snapshot fully obscures, 0 = fully revealed) and Destroy() when finished. ready is true once the snapshot has been captured (one frame after creation).
--- @field ready boolean True once the screen snapshot has been captured. False for the one frame between StartScreenTransition() and end-of-frame. Apply the visual change you want to fade *to* only after this becomes true.
--- @field hasDissolveMaterial boolean DIAGNOSTIC: true if the dissolve shader material was built, false if we're falling back to plain alpha fade.
ScreenTransitionLua = {}

--- CrossFade: Drive the dissolve. 1 = snapshot fully visible (hides new appearance), 0 = snapshot fully gone (new appearance revealed). Tween from 1 down to 0 over the desired transition duration. Internally maps to the shader's _Threshold uniform.
--- @param alpha number
--- @return nil
function ScreenTransitionLua:CrossFade(alpha)
	-- dummy implementation for documentation purposes only
end

--- Destroy: Release the snapshot RenderTexture and remove the overlay. Always call this when the transition is complete -- the RenderTexture is a screen-sized resource and is only freed here.
--- @return nil
function ScreenTransitionLua:Destroy()
	-- dummy implementation for documentation purposes only
end
