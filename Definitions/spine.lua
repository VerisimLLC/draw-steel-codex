--- @class spine Runtime control of the spine animation registry. Lets you query registry entries, override their placement parameters, and register per-entry refresh callbacks for the current session.
spine = {}

--- setDebug: Enable or disable verbose Debug.Log output for the spine system (fidget ticks, config changes, etc.). Off by default.
--- @param enabled boolean
--- @return nil
function spine.setDebug(enabled)
	-- dummy implementation for documentation purposes only
end

--- setDebugSlot: Set a slot-isolation debug filter on every active spine token. While set, only the named slot is visible (other slots are hidden by setting their slot color alpha to 0). Useful for figuring out which slot contains which body part, or for diagnosing draw-order / missing-attachment issues. Pass '*' to show all slots while staying in debug mode (handy for resetting visibility between checks). Pass nil to disable debug mode entirely so animations resume normal control of slot colors.
--- @param arg any
--- @return nil
function spine.setDebugSlot(arg)
	-- dummy implementation for documentation purposes only
end

--- setSkin: Set the active skin on every active spine token to the named skin. Useful for diagnosing whether attachments are bound under a different skin (e.g. 'base' or 'winded' rather than 'default'). Pass nil to revert to the default skin.
--- @param arg any
--- @return nil
function spine.setSkin(arg)
	-- dummy implementation for documentation purposes only
end

--- dumpTransforms: Print transform state (position/rotation/localScale) for every active spine token to the Console. Diagnostic aid for flip/scale/parallax issues. Includes drag-ghost CharacterTokens (which aren't in GameController.characterTokens).
--- @return nil
function spine.dumpTransforms()
	-- dummy implementation for documentation purposes only
end

--- listSlots: Print the slot names of every active spine animation in the world to the Console, indexed by draw order. Useful for finding the right name to pass to spine.setDebugSlot.
--- @return nil
function spine.listSlots()
	-- dummy implementation for documentation purposes only
end

--- register: Register a spine animation registry entry for the rest of this session. Required: id (string) - the unique identifier this entry will be looked up by (used in token portraitids of the form 'anim:<id>'). Optional model (string) - the base registry entry whose skeleton data and base parameters are inherited; defaults to id (the entry overrides itself / stands alone). When model differs from id, multiple variation ids can share the same underlying skeleton (e.g. id='lightbender-variant-1' model='lightbender'); a token swapping between same-model variations updates parameters in place without tearing down its SpineTokenRenderer. Other optional fields override the model's values; omitted ones inherit. World rendering: scale, xoffset, yoffset, bottomClip. Portrait camera framing (used by '#spine:tokenid' image lookups): portraitZoom (>1 zooms in, <1 zooms out), portraitXOffset, portraitYOffset (camera world offsets). Inspect / up-close portrait camera framing (used by '#spineinspect:tokenid' image lookups, exposed via CharacterToken.inspectPortrait): inspectZoom, inspectXOffset, inspectYOffset. These are independent from the portrait* fields and default to 0 (zoom 0 falls back to 1 == no scaling, offsets stay at 0). Layering / parallax: transforms is an ordered list of {slots, xoffset, yoffset, scale, frame} entries. Each entry covers a contiguous slot range starting at slots[1] (the cut point for spine-unity's SkeletonRenderSeparator); the first entry implicitly starts at the skeleton's first drawn slot. xoffset/yoffset are in the same token-local units as the registry-level xoffset/yoffset; scale is a multiplier (1 = same size as the parent spine). Set frame=true on exactly one entry to mark the front-of-frame cut: entries before it render BEHIND the token frame, that entry and after render IN FRONT. Omit transforms (or pass an empty list) for single-renderer mode where the whole spine draws on top of the frame. Eye IK: eyeik (bone name of a head/eye look-at controller bone driven by the owning token's lookAt position; pass nil/empty to disable), eyeMult (multiplier on the offset between the animation pose and the look-at target before the magnitude clamp; 1 = follow exactly, 0.5 = move halfway, 0 = ignore), and eyeRange (maximum allowed deviation magnitude from the animation pose, in spine local / parent-bone-local units; defines a circular window). Optional refresh - a function called at the end of CharacterToken.RefreshLua() for every token using this spine entry. The override is in-memory only and does not modify the asset on disk.
--- @param args {id: string, model: nil|string, scale: nil|number, xoffset: nil|number, yoffset: nil|number, bottomClip: nil|number, portraitZoom: nil|number, portraitXOffset: nil|number, portraitYOffset: nil|number, inspectZoom: nil|number, inspectXOffset: nil|number, inspectYOffset: nil|number, transforms: nil|{slots: nil|string[], xoffset: nil|number, yoffset: nil|number, scale: nil|number, frame: nil|boolean}[], eyeik: nil|string, eyeRange: nil|number, eyeMult: nil|number, refresh: nil|fun(token: CharacterToken)}
function spine.register(args)
	-- dummy implementation for documentation purposes only
end

--- modelrender: Register a standalone model render for the rest of this session, addressed via the '#spinemodel:<id>' image-id scheme. Required: id (string) - the unique identifier the render is looked up by (the '<id>' in '#spinemodel:<id>'). Optional model (string) - the spine animation registry entry to render; defaults to id. The render shows the model with its 'base' skin and looping '1_BASE_idle' animation, and periodically plays a random '1_BASE_fidget*' animation. Optional framing: width / height (target RenderTexture pixel size; default 768x1024, and the texture aspect is width/height); scale (zoom factor on top of the auto-fit to the model's bounds: 1 = tight fit, >1 zooms in / may crop, <1 zooms out / adds margin); offset ({x, y} array shifting the model within the frame in fractions of the view, where positive x moves it right and positive y moves it up). Re-registering the same id replaces the definition and rebuilds any live render.
--- @param args {id: string, model: nil|string, width: nil|number, height: nil|number, scale: nil|number, offset: nil|number[]}
function spine.modelrender(args)
	-- dummy implementation for documentation purposes only
end

--- modelgesture: Assert that a '#spinemodel:<id>' render is being actively gestured at right now -- e.g. spine.modelgesture('lightbender', 'pet') means the lightbender is being pet. The assertion lasts for the next couple of frames, so the gesture is sustained by calling this every frame (e.g. while a cursor strokes the image) and lapses shortly after the calls stop. While asserted, the render lerps toward the gesture's animation (an animation named '<gesture>' or '<digits>_<gesture>', e.g. 'pet' or '1_pet') over the idle, and lerps back to idle when it lapses -- the same blend used for petting animated tokens in the world. No-op if the skeleton has no animation matching the gesture name.
--- @param id string
--- @param gesture string
function spine.modelgesture(id, gesture)
	-- dummy implementation for documentation purposes only
end

--- getInfo: Returns information about a spine animation registry entry, including its current placement parameters and the names of all animations and skins on the skeleton. The `model` field is the underlying base entry whose skeleton data this entry uses (equal to id for entries that aren't variations). Returns nil if no entry with that id exists.
--- @param id string The registry entry id (e.g. "lightbender").
--- @return nil|{id: string, model: string, animations: string[], skins: string[], scale: number, xoffset: number, yoffset: number, bottomClip: number, portraitZoom: number, portraitXOffset: number, portraitYOffset: number, inspectZoom: number, inspectXOffset: number, inspectYOffset: number, transforms: {slots: string[], xoffset: number, yoffset: number, scale: number, frame: boolean, bottomClip: nil|number}[], eyeik: nil|string, eyeRange: number, eyeMult: number}
function spine.getInfo(idArg)
	-- dummy implementation for documentation purposes only
end

--- listEntries: Returns a list of every animated-token entry in the spine animation registry, regardless of ownership. Each row is { id = <registry name>, text = <registry name> }. Intended for admin / authoring UIs such as the shop editor's Animated Tokens picker. The id is the registry name used both in token portraitids ('anim:<id>') and as the name an AnimatedTokens shop item grants.
--- @return {id: string, text: string}[]
function spine.listEntries()
	-- dummy implementation for documentation purposes only
end

--- clearOverrides: Clear all session overrides on the spine registry, including any registered refresh callbacks. Reverts to whatever's serialized in the registry asset.
--- @return nil
function spine.clearOverrides()
	-- dummy implementation for documentation purposes only
end

--- setCurrentCastingToken: Set the global 'current casting token' used by spine eye-IK. Other spine tokens with an eye IK bone will turn to look at this token while it's set. If the casting token itself has eye IK, it will look at the first target set by setCurrentCastingTargets. Pass nil to clear. Accepts either a CharacterToken or a token id string.
--- @param tokenArg nil|CharacterToken|string
function spine.setCurrentCastingToken(tokenArg)
	-- dummy implementation for documentation purposes only
end

--- setCurrentCastingTargets: Set the global 'current casting target tokens' list used by spine eye-IK. The casting token (see setCurrentCastingToken) will look at the first valid target in this list. Pass nil or an empty list to clear. Accepts an array of CharacterTokens or token id strings.
--- @param tokensArg nil|(CharacterToken|string)[]
function spine.setCurrentCastingTargets(tokensArg)
	-- dummy implementation for documentation purposes only
end

--- clearCurrentCast: Clear both the current casting token and its targets. Equivalent to setCurrentCastingToken(nil) + setCurrentCastingTargets(nil). Spine eye-IK on all tokens reverts to its idle (no look-at) behavior.
--- @return nil
function spine.clearCurrentCast()
	-- dummy implementation for documentation purposes only
end
