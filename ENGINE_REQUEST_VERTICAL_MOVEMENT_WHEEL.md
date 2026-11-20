# Engine request: mouse wheel changes height for every vertical movement type

**Requested by:** Ricky, 2026-11-20. **Status:** open. **Needs:** an engine (C#) change; the Lua side is small and described below. Background on every vertical-movement mechanism: `HANDOVER_vertical_movement.md`.

## The ask

While dragging a token, the mouse wheel sets the height the move ends at. Today that works only for a creature that is flying, or can fly and is walking. Make it work for every creature that can move vertically at that spot:

1. **Swimming.** Wheel down dives, wheel up rises, stopping at the bed and at the water surface.
2. **Climbing.** Wheel up or down climbs a wall the creature can climb at the token's location, stopping at the top of the wall (and the ceiling, for a creature that can cling to one).
3. **Burrowing.** Wheel down digs, wheel up rises, never above the ground surface.

The same dial should work on pathfound ability moves (Advance and similar), through the existing `flightAltitude` option.

## Why it needs the engine

- The drag wheel is handled inside the engine. Lua cannot claim the wheel during a plain token drag or change the drag's destination height.
- `CharacterToken:MarkMovementArrow` and `CharacterToken:Move` take `flightAltitude`, but the definitions limit it to "a token that is flying, or can fly and is walking". For any other token it is ignored. The Lua wheel for ability moves (`DrawSteelActionBar._flight`, `AbilityRelocateCreature`) already feeds it, so it needs no new plumbing once the engine honours it.
- The clamping rules differ per type and live with the pathfinder and terrain code: the water surface and bed (`MapManifest` water level, `token.distanceBelowGround`), the climbable wall height (`token.canCurrentlyClimb`), and the ground and ceiling for burrowing.

## Proposed change

- **A. Generalize the drag wheel.** Give the wheel to a drag whenever the token's current move type, or the move type the keys would switch it to, can change height at the start square. Today's rule is fly (or walk and can fly). Add: swim, climb where `canCurrentlyClimb`, burrow when `CanBurrow()`. Not for forced (alt) or teleport (ctrl) drags, as now.
- **B. Honour `flightAltitude` for those types.** Rename it in the definitions if wanted (for example `altitudeOverride`); keep `flightAltitude` working. The altitude is absolute, spread across the squares crossed, clamped as above, and `path.destination.altitude` reports where it ended.
- **C. Cost.** Keep the existing rule (one extra square per square of climb beyond one per square moved) for fly. For swim, climb and burrow, charge what each type already charges for vertical steps, so the tooltip's "Uses N" stays truthful.
- **D. Report capability to Lua.** Expose a read-only value, for example `token.canDialAltitude` or a `path.altitudeDialable` flag on the drag, so Lua can show the hint only when the wheel will actually work. Without it Lua has to re-derive the engine's rule and will drift.

## Lua side, ready to ship once the engine lands

- Generalize the "flight-wheel" `InputHint` (`DrawSteelActionBar.lua`) from "Use {wheel} to fly up or down" to a hint named for the source: "Use {wheel} to swim up or down", "to climb up or down", "to dig up or down". Show it from the engine's capability value (D), for plain drags and ability moves.
- Let `DrawSteelActionBar._flight.CreatureCanDial` accept the new move types.
- Remove the "Hold Alt + up/down" Codex Callout (`GameHud.VerticalMovementCallout`, `DSHud.lua`), which exists only because the wheel is fly-only today.

## Acceptance

- Drag a swimming token: the wheel dives and surfaces, the arrow and tooltip show the end altitude and the cost, and the move ends there.
- Drag a token next to a climbable wall: the wheel climbs it, stopping at the top.
- Drag a burrower: the wheel digs down, stopping before it would rise above the ground.
- A creature that cannot move vertically at that spot gets no wheel (the camera zooms as usual) and no hint.
- Flying creatures behave exactly as today.
- Ability moves (Advance and similar) honour the dialed height for the same types.
- Forced and teleport drags are unchanged.

## Open questions for the engine side

- Does a swimmer's wheel need to hand off to flying at the surface, as the altitude box does today (only at the surface can a flier take off)?
- Should a creature next to a wall that both flies and climbs get the fly dial, as now?
- For a non-climber, how does the engine price climbing today? That is the number the tooltip must match.
