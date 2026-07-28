# Wielded Items on Tokens (Visible Held Items)

How equipped items (weapons, shields, torches, belt accessories) render as visible
sprites attached to a creature's token. Originally built for 5e; the full pipeline
already exists in this codex and the engine. To make Crows content show held items,
you author item data -- no engine or plumbing work should be needed.

## Data flow (end to end)

1. **Item opt-in.** An equipment entry in `tbl_Gear` is shown on tokens if
   `equipment:DisplayOnToken()` is true (`DMHub Game Rules/Equipment.lua:257`):
   `displayOnToken` is not false (defaults true) AND `iconid` is non-empty.
   Whether it *can* be held: `equipment:CanWield()` (`Equipment.lua` ~line 140) =
   `isWeapon` or `isShield` or has `emitLight` or explicit `canWield = true`.
   Belt display uses `equipOnBelt = true` instead.

2. **Which items are in hands.** `creature:GetWieldObjects()`
   (`DMHub Game Rules/Creature.lua:4058`) -> `GetLoadoutInfo(self.selectedLoadout)`.
   It reads `creature:Equipment()` (slotid -> itemid map) using the slot table
   `creature.EquipmentSlots` (defined just above, ~`Creature.lua:4000`): slots
   `mainhand1/offhand1` .. `mainhand3/offhand3` (per loadout) plus `accessory`
   slots for the belt. Returns `{ mainhand = itemid|nil, offhand = itemid|nil,
   belt = {itemid,...} }`. Filters:
   - mainhand/offhand: item must pass `DisplayOnToken()`.
   - belt: item must pass `DisplayOnToken()` AND have a custom `itemObjectId`
     (plain icons are not shown on the belt).

3. **The visual object.** `equipment:GetWieldObject()`
   (`DMHub Game Rules/Equipment.lua:147`) returns an object-instance JSON:
   - If the item has `itemObjectId`, that authored map object asset is used
     verbatim (`{ assetid = itemObjectId }`). This is how you get a nice
     hand-drawn weapon sprite instead of the inventory icon.
   - Otherwise it generates one from the item's inventory icon:
     `ObjectComponentCore` (scale 0.2, drop shadow, sublayer
     `EffectsAboveTokens`), an optional `ObjectComponentLight` built from the
     item's `emitLight {radius, color}` (this is how a held torch lights the
     map), and an `ObjectComponentWield` component with `offsetx/offsety`.

4. **C# attach.** On every token refresh, `CharacterToken.RefreshLua`
   (`Assets/Scripts/CharacterToken.cs:5263-5306`) calls
   `properties:GetWieldObjects()` (or uses `token.wieldedObjectsOverride` if a
   Lua script set it -- handy for previews/testing). Changed ids flow into
   `SetObjects` (`CharacterToken.cs:18443`), and `SpawnWieldObject`
   (`CharacterToken.cs:18478`) looks the item up in `tbl_Gear`, calls its
   `GetWieldObject()`, deserializes the JSON into an `ObjectInstance`, and
   instantiates a `LevelObject` parented to one of three anchor Transforms on
   the token prefab: `_mainHand`, `_offHand`, `_belt`
   (`CharacterToken.cs:4596`, serialized on the prefab). Because the object is
   parented to the token it moves, flips, and scales with it automatically.
   Objects are `ephemeralObject` -- they are never saved to the map.

5. **Spawn/despawn polish.** `ObjectComponentWield`
   (`Assets/Scripts/LevelObject.cs:5553`) animates a 0.4s equip/unequip:
   drops in from +0.3 tiles with fade and a 1.2x -> 1x scale settle, reverse on
   unequip (`DespawnWield`, removal at `CharacterToken.cs:18170`). It also
   applies the per-item `xoffset/yoffset` and an optional `image` swap.

6. **Networking is free.** Nothing extra is replicated: the held visuals are
   derived purely from the creature's equipment data, which already syncs, so
   every client computes and renders the same thing locally.

## What to do for new (Crows) content

For each item that should appear in a creature's hand:

- Give it a good `iconid`, and set the right flags: `isWeapon`/`isShield`, or
  `canWield = true` for generic holdables, `equipOnBelt = true` for belt items,
  `emitLight = { radius = ..., color = {...} }` for light sources.
- Optional but recommended for hero-facing items: author a dedicated object
  asset and set `itemObjectId` on the item so the held sprite is purpose-drawn
  rather than the shrunken inventory icon. The Item Editor UI already exposes
  this ("can be wielded" checkbox + wield-object preview -- see
  `DMHub Compendium/ItemEditor.lua:303` and the `displayOnToken` toggle at
  `:2255`); the editor edits the wield object via the object-properties dialog
  `previewType = "wield"` path.
- Make sure the creature actually has the item equipped in a hand slot of its
  **selected loadout** (`equipment.mainhand1` etc. via
  `creature:SetEquipmentInSlot`), not merely present in inventory.
- Items that should never render (e.g. story items with icons) can set
  `displayOnToken = false`.

## Testing tips

- Set `token.wieldedObjectsOverride = { mainhand = itemid }` from a console /
  MCP Lua snippet to force a token to show an item without touching equipment;
  set it back to nil to restore normal behavior.
- Equip/unequip through the character sheet and confirm the drop-in/fade-out
  animation plays and that torches light the map (the LIGHT component path).
