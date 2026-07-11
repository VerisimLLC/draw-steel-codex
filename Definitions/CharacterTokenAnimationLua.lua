--- @class CharacterTokenAnimationLua Per-token animation interface acquired via `token.animation`. Provides spawn primitives (Light / Billboard / PlayEffect), transform control (Tween / SetVisible), and a sound passthrough. Spawns made during a scripted animation are tracked and stopped when the animation ends.
CharacterTokenAnimationLua = {}

--- Light: Spawn a circle-light burst at the token (default) or at args.pos. Args: color (Color), radius (number), innerRadius (number), duration (number), fadein (number, optional), fadeout (number, optional), pos (Loc, optional), delay (number, optional).
--- @param args table
function CharacterTokenAnimationLua:Light(args)
	-- dummy implementation for documentation purposes only
end

--- Billboard: Spawn a video billboard (e.g. teleport.webm). Default position is the token; provide args.pos to fix in world. Args: video (string), blend (string, optional, 'add'|'alpha'), scale (number, optional), playbackSpeed (number, optional), hsv (LuaVector4, optional), tint (Color, optional), pos (Loc, optional), delay (number, optional).
--- @param args table
function CharacterTokenAnimationLua:Billboard(args)
	-- dummy implementation for documentation purposes only
end

--- PlayEffect: Spawn a particle effect prefab from TokenEffectIndex. Default position is the token (parented so the effect rides Tween-driven offsets); provide args.pos to fix in world. Args: id (string, prefab name), scale (number, optional), rotation (number = degrees about Z / in-plane spin, OR a {x,y,z} euler table for 3D reorientation; optional), tint (Color, optional), looping (boolean, optional), ttl (number, optional, required if looping), pos (Loc, optional), delay (number, optional). Particles are spawned with Hierarchy scaling so scale/rotation propagate to nested emitters, and World simulation so rate-over-distance emitters trail correctly.
--- @param args table
function CharacterTokenAnimationLua:PlayEffect(args)
	-- dummy implementation for documentation purposes only
end

--- Tween: Tween the token's visual transform (purely cosmetic -- the logical position is unaffected). Args: translate (Loc, optional destination), duration (number, seconds; 0 = snap), easing (string, optional: 'linear'|'easeIn'|'easeOut'|'easeInOut'). Fire-and-forget; use sleep(duration) to wait it out. Starting a new Tween supersedes any active one.
--- @param args table
function CharacterTokenAnimationLua:Tween(args)
	-- dummy implementation for documentation purposes only
end

--- SetVisible: Hide or show every Renderer and Canvas on the token (sprite, frame, spine, shadow, HUD). Records which were enabled so SetVisible(true) only re-enables those (a token already hidden by fog stays hidden). Engine guarantees the token is restored visible when the animation finishes; SetVisible(true) is only needed if the script wants visibility back partway through.
--- @param visible boolean
--- @return nil
function CharacterTokenAnimationLua:SetVisible(visible)
	-- dummy implementation for documentation purposes only
end
