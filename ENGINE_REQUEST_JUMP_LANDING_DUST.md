# Engine request: landing dust on jump landings

**Requested by:** Ricky, 2026-09-11. **Status:** open. **Needs:** an engine (C#) change; the Lua side is ready.

## The ask

Play the dust puff the engine already shows when a creature falls and lands, in two more places:

1. **Ogre Juggernaut, Earth-Breaking Jump.** The jump is a `token:Move` with `movementType = "jump"` (via the standard Jump ability's relocate behavior). When the jump animation lands at its destination, play the landing dust there.
2. **Ogre malice feature Shockwave.** The ogre hops in place (the Hop In Place behavior, codex PR #320): a same-square teleport that runs a registered teleport style, which tweens the token up two tiles and back. Play the landing dust when it comes back down.

Both should play on every client, at the landing frame, the same way the fall dust does today.

## Why it needs the engine

The fall-landing dust is not reachable from Lua. It has no entry in `TokenEffectIndex` (the prefab list behind `token.animation:PlayEffect`), the Lua `TokenEffects` registry, or the emoji table, so a codex-side change cannot play it. The closest prefab in the index (`Effect_21_GroundScatter`) is a lava burst.

## Proposed change

- **A. Jump landings (covers item 1).** Where a `movementType = "jump"` move finishes its landing (the path that already decides `creature:GetFallType` and calls `creature:PlayLandingFootstep` for on-feet landings), spawn the fall-landing dust prefab at the landing square, on every client.
- **B. Expose the prefab (covers item 2).** Register the fall-landing dust prefab in `TokenEffectIndex` under a stable id, proposed `LandingDust`, so Lua can call `token.animation:PlayEffect{ id = "LandingDust" }`. The Hop In Place animation already has the landing frame; it will call this once the id exists.

B alone would also cover item 1 if `token:Move` ever reports the animation's landing to Lua, but today `Move` returns when the logical move completes, before the arc finishes, so A is the reliable path for real jumps.

## Acceptance

- Earth-Breaking Jump: dust at the destination square as the ogre lands, seen by the Director and players.
- Shockwave: dust under the ogre as the hop lands, seen by the Director and players.
- No dust on non-jump moves, and the existing fall-landing dust is unchanged.
