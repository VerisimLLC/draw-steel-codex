# Ongoing effects marked "Hidden on token" only (2026-11-05)

93 effects have "Hidden on token" ticked but not "Hidden". Sorted by name and description
only; nothing checked in play. Why it matters: History should leave pure markers out, but
"Hidden" cannot be used for that, because the Tac panel's effect chips (where a Director
removes an effect by hand) only list effects without "Hidden"
(`Draw Steel Core Rules/MCDMCharacterPanel.lua:10779`, `:12939`). James's point.

## Suspected markers

A. The description says it is internal (8): Bullseye Tier 1 (marker), Burning Ash Target,
Clinging Muck Marker, Envy Payload, Envy Primed, Invisible Marker, Shared Maneuvers Echo,
Shriek Rider.

B. Tracks a use, a turn or a target (15): Moved This Turn, Started their turn Hidden,
BlitzTracking, BlitzUsed, Radical Fantasia Free Triggered Action Used, Used Moonlight
Sonata, Used Posthumous Retirement, Revenge Expiring, Source of Earth Damage Taken,
Targeted by Time Bomb, Dramatic Reveal Target, Chain Reaction target, Synaptic Dissipation
damage trigger, Vengeance, One Vial Makes You Faster - stored.

C. A tag with no description, probably a marker (16): Affinity Type - Acid, Cold,
Corruption, Fire, Lightning, Poison; Companion Creature, Guardian, Prowler, Spark; Gloom
Squad Member, Gloom Squad Summoned; Death Cultist Has Minions; Cursed Caster; Mazed Caster;
Blitz Tactics.

## The 11 unsure, checked in the data (2026-11-06)

Marker: Portfolio Champion (no modifiers, a tag from Call Forth), so 40 markers in all.
Real, so they show in History: 10 more Stamina (+10 Stamina), Howling Ward (an aura), Loner Ally (a
trigger), Provoking Nettles (a trigger), Saved in the Edit (all four change immunity, weakness, speed
or stability), Spirit Controls (a proficiency), Store Potion (grants an ability).

## Real effects players care about (43, plus the 10 above)

Absence of All Light, Bleeding, Bloodbound, Body Armor, Bully The Weak, Cannot use Hide,
Chain of Sea and Sky, Coat the Blade, Corrupted Mentor, Delicious Meal, DolefulVisions,
Dramatic Reveal, Dread and Terror, Epic - Ally, Essence of Smoke, Hallucinatory, Levitate 1,
Lingering I, Lingering II, Metamorphic (Concealed, Large, Vicious), Order, Revitalizing
Ritual, Rivalry, Scene Partners, Sharing Head, Size 2, Size 3, Size 4, Snack Attack, Source
of Earth, Speed +1, Stop-'n-Go Coin (Green, Red, Spinning), Thorn Dragon Domain, Time Bomb
Ticking, Tower Shield Smash Ally, Vanish, Vengeance Mark (Rival), Visible Fangs, Your
Triumphs Are Remembered.

## What James needs to do

Nothing unless he disagrees. A wrong tick only hides that effect from History and is one checkbox to
undo. Judgement calls left as markers: Used Moonlight Sonata, Used Posthumous Retirement, Vengeance,
the Companion tags, the Affinity Types. The data pass happens at build time, with the Codex closed.
