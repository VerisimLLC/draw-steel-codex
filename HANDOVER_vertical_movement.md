# Handover: how vertical movement works in the Codex (draw-steel-codex)

Written 2026-11-20 as the starting point for a design conversation: "how does vertical
movement actually work, and can we improve it?" This is an inventory of what exists, not
a proposal. Items marked **(verify)** were read from code but not exercised live.

## Why this came up
We added a Codex Callout under the drag-move tooltip that tells a creature which keys
change its height ("Climb: Hold Alt + up-arrow or Alt + down-arrow to change height.").
Building it meant listing every way a creature can go up or down, and the answer is
scattered across the engine, the character panel, abilities and keybinds. The callout
code is `GameHud.VerticalMovementSource` / `VerticalMovementCallout` in
`Draw Steel UI/DSHud.lua`, on branch `claude/codex-callout-boxes-12025f` (builds on PR #481).

## The core idea: a creature has a "current move type"
`creature:CurrentMoveType()` is one of `walk`, `fly`, `swim`, `climb`, `burrow` (also
`teleport` as a speed). Vertical keys act on whatever the current type is. The character
panel altitude box (`TacPanel.AltitudeBox`, `Draw Steel Core Rules/MCDMCharacterPanel.lua`
~5960) is the clearest statement of the rules: it is visible when the creature
`CanFly()`, `token.canCurrentlyClimb`, `CanBurrow()`, is swimming, or is ceiling-clinging.
Its "+" / "-" buttons, and the keybinds, pick the move type to switch to in this order:
swim (if diving) -> fly (if CanFly) -> climb (if canCurrentlyClimb) -> burrow (if CanBurrow).

## Ways a creature can move vertically on its own (player-driven)

1. **Fly** - a fly speed (`creature:CanFly()`, `GetSpeed("fly") > 0`).
   - Vertical flight needs `creature:CanFlyVertically()`: false when the custom attribute
     "Horizontal Flight Only" is set (the levitation from the Ghost's Spirited Away).
     Such a creature that is next to a climbable surface climbs instead
     (`TacPanel.VerticalFlightMoveTypeOrWarn`); otherwise a "Can only fly horizontally"
     float label shows and nothing happens.
   - During a drag, the engine gives fliers (and walkers that can fly) the **mouse wheel**
     to dial a height; the bottom-of-screen `InputHint` "flight-wheel" says so
     (`DrawSteelActionBar.lua` ~1285). Not offered on forced (alt) or teleport (ctrl) drags.
   - Ability moves (Advance etc.) use the same wheel via `DrawSteelActionBar._flight`;
     the dialed height is capped at the ability's distance.
   - Coming down: the "Drop to Ground" ability (`ActivatedAbility.GetDropToGroundAbility`,
     `MCDMActivatedAbility.lua` ~1414) - player-controlled fliers only, normal fall damage;
     it sets `_tmp_droppingToGround` so `CanFly()` reads false for the drop.

2. **Climb** - walls and similar surfaces.
   - The engine decides, per location, whether the creature may climb right now:
     `token.canCurrentlyClimb` ("can climb in the current location it is in now").
     Climbing does not need a climb speed: `creature:CanClimb()` is just "not prone".
     A creature with a climb speed moves at that speed; others pay extra for climbing.
     **(verify)** how the engine prices climbing for a non-climber.
   - A path that needs climbing is flagged `path.hasClimbing` and the tooltip adds a red
     "This path requires climbing." line.
   - `canCurrentlyClimb` is evaluated at the token's current spot, so a creature one
     square from a wall does not get it; the user's mental model is "next to a climbable wall".
   - **Ceiling cling**: natural climbers (`IsClimber`, climb speed >= walk speed) can move
     up at the ceiling and cling upside down (`creature:CanClingToCeiling`,
     `IsClingingToCeiling`, `token.isCeilingClinging`, Creature.lua ~4980). Movement is
     then restricted to tiles with ceiling overhead; moving down lets go.

3. **Swim** - water.
   - Map water level (`WATER_LEVEL_REFERENCE.md`, `MapManifestLua.lua`) or painted water.
     Ground at least 1 below the level is deep water: the creature floats at the surface
     and may dive to the bed; less than 1 is shallow water (difficult terrain).
   - In the altitude box, anyone in water can dive (`CurrentMoveType() == "swim"`),
     even without a swim speed. Down = dive (stops at the bed), up = surface; only at the
     surface can a flier take off. `token.distanceBelowGround` tells surface from underwater.
   - Items worth checking: **(verify)** what happens to a non-swimmer in deep water.

4. **Burrow** - a burrow speed (`creature:CanBurrow()`).
   - "-" digs down and switches the move type to burrow; never rises above ground level
     in the Dig maneuver. The attribute "Cannot Drag Underground" (Force of Earth's Stone
     Swim) makes the creature release grabbed creatures first
     (`ActivatedAbilityDigVerticalBehavior.ReleaseGrabsBeforeGoingUnderground`).
   - The **Dig maneuver** is a separate path: `ActivatedAbilityDigVerticalBehavior`
     (`Draw Steel Ability Behaviors/AbilityFall.lua` ~182) - a purely vertical move chosen
     with +/- buttons and Confirm, distance = a GoblinScript (default "Tile Size").

5. **Floors** - moving between map floors (`path.destination.floor ~= token.loc.floor`,
   tooltip " (+1 Floor)"). Altitude is "floorAltitude" relative to the current floor and
   "altitude" absolute. **(verify)** how stairs/ladders/floor openings are modelled.

## Ways vertical position changes that are NOT the creature's own choice
- **Falling** - `AbilityFall.lua`; unsafe iff (N - Fall Reduction) >= 2, safe distance is
  Fall Reduction + 1, landing in water lowers effective height by 4; Stop Fall Damage
  makes any drop safe. Fliers hover instead of falling. `path.fallDistance` drives the
  tooltip's "Safely drops / Falls N squares" lines.
- **Forced movement with a vertical component** - lift/push up, the ceiling cap (engine
  caps a lift at slab-1 only when there is a ceiling; ground above the cap blocks all
  lifts). See memory notes "Vertical forced-move ceiling rule" and "Lift into air / fly
  pattern" (a fly duration effect + `lift_vertical`).
- **Teleport** - `path.teleport`; cost counts the vertical dimension
  (`max(lateral, abs(altitudeDelta))`, DSHud.lua ~179).
- **Effects that raise/lower a creature** - e.g. rising each turn, falling when the effect
  ends; these do not ask `CanFlyVertically`.
- **Water level changes** float tokens (`MapWaterLevel.FloatTokensAfterLevelChange`).
- **Mounts and grabs** - a mount carries its rider; the engine pulls grabbed creatures
  along with any move, including vertical ones (AbilityFall.lua ~621).

## The controls, and where they are inconsistent
| Control | Where | Works for |
|---|---|---|
| Fly Token Up / Down keybinds (default Alt + Up / Alt + Down; commands `flyup`, `flydown`) | `Keybinds.lua` ~490; wrapped in `MCDMCharacterPanel.lua` ~84 | fly, and climb (wrapper reroutes). Engine original handles the rest |
| Altitude box "+" / "-" buttons | `TacPanel.AltitudeBox` | fly, climb, burrow, swim dive, cling |
| Mouse wheel during a drag | engine + "flight-wheel" InputHint | fliers only |
| Drop to Ground ability | Move drawer | fliers only |
| Dig maneuver (+/- and Confirm) | ability | burrowers |
| Callout under the drag tooltip (new) | `DSHud.lua` | names the source and the keys |

Inconsistencies to discuss:
- Wheel exists for fliers only; climbers, swimmers and burrowers have only keys/buttons.
- Alt is also the engine's forced-move drag modifier (`path.forced`). The callout says
  "Hold Alt + up-arrow" during a drag; whether holding a key mid-drag actually changes
  the drag's destination height for each mode is **unverified** - confirm in a real drag.
- The keybind wrapper reroutes climbers but the engine handles swim/burrow; two code
  paths decide "which move type does Up use".
- A flier who is also next to a wall: both fly and climb apply; the callout prefers the
  current move type, then fly, then climb, then burrow.
- Climb availability is "right now at this location", so the hint and the capability
  vanish one square away from the wall. The drag path may still cross a climb.
- Walkers that can fly are treated as able to dial height (`CurrentMoveType() == "walk"`
  special case) while swimmers/burrowers/climbers are explicitly excluded from the wheel.

## Key API reference
- `creature:CurrentMoveType()`, `creature:SetAndUploadCurrentMoveType(type)`
- `creature:CanFly()`, `IsFlying()`, `CanFlyVertically()`, `CanBurrow()`, `CanSwim()`,
  `CanClimb()`, `CanClingToCeiling()`, `IsClingingToCeiling()`, `GetSpeed(type)`
- `token.canCurrentlyClimb`, `token.distanceBelowGround`, `token.floorAltitude`,
  `token.altitude`, `token.isCeilingClinging`, `token:MoveVertical(newAltitude)`
- `path.hasClimbing`, `path.fallDistance`, `path.waterSteps`, `path.forced`,
  `path.teleport`
- `dmhub.GetCommandBinding("flyup")` returns e.g. "alt+up"
- `GameHud.VerticalMovementSource(token)` -> "fly" | "climb" | "swim" | "burrow" | "cling" | nil

## Questions worth putting to the other agent
1. Should there be one rule for "which move type does Up/Down use", in one place?
2. Should climbers, swimmers and burrowers get the wheel like fliers?
3. Can a held key during a drag actually set the destination height for every mode? What
   does the engine do with the drag path's altitude today?
4. Should "can climb here" look at the destination or the path, not only the start?
5. How is the cost of climbing, swimming and burrowing shown to the player before they move?
6. Do the Alt-drag (forced move) and Alt+arrows share a modifier conflict?

## Gaps in this document
Nothing here was exercised live except `canCurrentlyClimb`, the keybind format, and the
callout itself. The engine C# (drag wheel, climb pricing, stairs/floors) is not in this
repo and was not read.
