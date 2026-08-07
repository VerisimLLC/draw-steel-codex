# Shadow Elf Reference

Definitive rules text for the Shadow Elf monster group, extracted verbatim from
[`monster-reference.md`](monster-reference.md) (the released Draw Steel *Monsters* book):

| Source range | Contents |
|---|---|
| `monster-reference.md:6733-7410` | Shadow Elf Malice + 13 statblocks + Brush Stalker |
| `monster-reference.md:25735-25800` | Shadow Elf Shade (lives in the Retainers chapter) |

## Notation

Potency is written `X<N`, where `X` is the characteristic the target tests and `N` is
the threshold -- e.g. `I<2 bleeding (save ends)` means "if the target's Intuition is
less than 2, they are bleeding (save ends)".

| Symbol | Characteristic |
|---|---|
| `M<N` | Might |
| `A<N` | Agility |
| `R<N` | Reason |
| `I<N` | Intuition |
| `P<N` | Presence |

The source PDF extraction renders these with a mangled glyph (`i<2]`, `a<3]`, ...);
they are normalized here. Nothing else has been altered -- damage values, tier
thresholds, effect text, and trait wording are verbatim.

## Compendium status (snapshot: 2026-07-31)

All statblocks below except **Brush Stalker** exist in
`data/monsters/shadow-elf-*.yaml`, under the `Shadow Elf` folder
(`e69fe1fa-2c1b-4f55-b551-8cc2e91e06c6`). Level, role, and EV match this reference
exactly. The three Malice features are in
`data/objectTables/monstergroup/shadow-elf.yaml`.

| Statblock | yaml | Ability implementation |
|---|---|---|
| Cloak, Nightstrike, Sniper, Dusk Mage | present | Silver / Gold |
| Knightfell, Luminator, Panther | present | Silver / Gold |
| Duskcaller, Moondancer | present | Silver, 1 narrative |
| Assassin, Mournblade, Noctis Mage | present | Silver / Gold |
| Eclipse | present | Silver / Gold, 3 narrative |
| **Shade** | **partial** | **Unimplemented, and abilities are missing** |
| **Brush Stalker** | **absent** | -- |

Known gaps to close:

1. **Brush Stalker** has no yaml anywhere in `data/`. (`umbral-stalker.yaml` is an
   unrelated level 1 Horde Ambusher and is not this monster.)
2. **Shade** (`data/monsters/shadow-elf-shade.yaml`) carries only the `Of the Umbra`
   trait plus a single ability. That ability is *named* "Shadow Dagger" but its text is
   the signature **Gloom Dagger** ("gain a surge"). Missing outright: `Duskfall`,
   `Slow-Poison Needle` (level 7 advancement), and the real `Shadow Dagger`
   (level 10 advancement). It has no `implementation` field, so it reads as
   Unimplemented.
3. Thirteen legacy Pactreon-manuscript statblocks are still visible in the same folder
   under their pre-release names -- Blot, Stipple, Crosshatchet, Ditherite, Contourze,
   Celstrike, Killhouette, Nullstroke, Obscurse, Shadesong, High Light, Streak, Flash.
   They are superseded by the statblocks below (Nullstroke is the old Eclipse; Blot is
   the old Cloak) and are `hidden: false`, so they appear alongside the current
   versions in the bestiary.

---

## Shadow Elf Malice

**Malice Features**
At the start of any shadow elf's turn, you can spend Malice to activate one of the following features.

### Watch Me Disappear (3 Malice)
Each shadow elf acting this turn can attempt to hide as a free maneuver if they have concealment.

### Extra Dimension (5 Malice)
When any shadow elf acting this turn makes a strike against a target who has I<2 in addition to the strike's regular effects, the target is bleeding (save ends) or slowed (save ends).

### Home Is Where the Hurt Is (10 Malice)
The shadow elves synthesize a concentrated pocket manifold reminiscent of Equinox and graft it onto the encounter map. Until the end of the encounter, all creatures can see shadow elves in full color, and shadow elves no longer benefit from their Of the Umbra trait. Additionally, the potency of all shadow elf abilities increases by 2, and any enemy making a saving throw against an effect imposed by a shadow elf ability must roll an 8 or higher as they feel the effect across two worlds.

---

## Shadow Elf Cloak
*Level 4 Minion Harrier*
*Keywords: Fey, Humanoid, Shadow Elf*
*EV 6 for four minions*

| Stat | Value |
|------|-------|
| Size | 1M |
| Speed | 8 |
| Stamina | 8 |
| Stability | 0 |
| Free Strike | 2 |

**Immunities:** --
**Weaknesses:** --
**Movement Modifiers:** Climb
**With Captain:** +2 bonus to speed

| MGT | AGL | REA | INU | PRS |
|-----|-----|-----|-----|-----|
| +3 | +1 | 0 | 0 | 0 |

### Stick and Poke (2d10 + 3)
*Signature Ability*
*Melee, Strike, Weapon*
*Main action*
*Melee 1 | One creature or object per minion*

- **Tier 1 (<=11):** 2 damage
- **Tier 2 (12-16):** 4 damage
- **Tier 3 (17+):** 6 damage

**Effect:** The cloak shifts up to 2 squares.

### Trait: Of the Umbra
The cloak ignores concealment created by darkness. While the cloak is in direct sunlight, they have damage weakness 3. While the cloak has concealment, they have damage immunity 3.

---

## Shadow Elf Nightstrike
*Level 4 Minion Ambusher*
*Keywords: Fey, Humanoid, Shadow Elf*
*EV 6 for four minions*

| Stat | Value |
|------|-------|
| Size | 1M |
| Speed | 5 |
| Stamina | 8 |
| Stability | 0 |
| Free Strike | 3 |

**Immunities:** --
**Weaknesses:** --
**Movement Modifiers:** Climb
**With Captain:** Gain an edge on strikes

| MGT | AGL | REA | INU | PRS |
|-----|-----|-----|-----|-----|
| +1 | +3 | 0 | +1 | 0 |

### Vault (2d10 + 3)
*Signature Ability*
*Melee, Strike, Weapon*
*Main action*
*Melee 2 | One creature or object per minion*

- **Tier 1 (<=11):** 3 damage
- **Tier 2 (12-16):** 5 damage
- **Tier 3 (17+):** 7 damage

**Effect:** The nightstrike shifts to leap over the target and into an unoccupied space adjacent to the target, opposite from the nightstrike's original space.

### Trait: Of the Umbra
The nightstrike ignores concealment created by darkness. While the nightstrike is in direct sunlight, they have damage weakness 3. While the nightstrike has concealment, they have damage immunity 3.

---

## Shadow Elf Sniper
*Level 4 Minion Artillery*
*Keywords: Fey, Humanoid, Shadow Elf*
*EV 6 for four minions*

| Stat | Value |
|------|-------|
| Size | 1M |
| Speed | 5 |
| Stamina | 7 |
| Stability | 0 |
| Free Strike | 3 |

**Immunities:** --
**Weaknesses:** --
**Movement Modifiers:** Climb
**With Captain:** +2 damage bonus to strikes

| MGT | AGL | REA | INU | PRS |
|-----|-----|-----|-----|-----|
| +1 | +3 | 0 | 0 | 0 |

### Lumina Arrow (2d10 + 3)
*Signature Ability*
*Ranged, Strike, Weapon*
*Main action*
*Ranged 7 | One creature or object per minion*

- **Tier 1 (<=11):** 3 damage
- **Tier 2 (12-16):** 5 damage
- **Tier 3 (17+):** 7 damage

**Effect:** The next strike made against the target gains an edge.

### Trait: Of the Umbra
The sniper ignores concealment created by darkness. While the sniper is in direct sunlight, they have damage weakness 3. While the sniper has concealment, they have damage immunity 3.

---

## Shadow Elf Dusk Mage
*Level 4 Minion Hexer*
*Keywords: Fey, Humanoid, Shadow Elf*
*EV 6 for four minions*

| Stat | Value |
|------|-------|
| Size | 1M |
| Speed | 5 |
| Stamina | 7 |
| Stability | 0 |
| Free Strike | 2 |

**Immunities:** --
**Weaknesses:** --
**Movement Modifiers:** Climb
**With Captain:** Gain an edge on strikes

| MGT | AGL | REA | INU | PRS |
|-----|-----|-----|-----|-----|
| 0 | +3 | +2 | 0 | 0 |

### Gloom Bolt (2d10 + 3)
*Signature Ability*
*Magic, Ranged, Strike*
*Main action*
*Ranged 5 | One creature or object per minion*

- **Tier 1 (<=11):** 2 damage
- **Tier 2 (12-16):** 4 damage; A<2 slowed (save ends)
- **Tier 3 (17+):** 6 damage; A<3 slowed (save ends)

### Trait: Of the Umbra
The dusk mage ignores concealment created by darkness. While the dusk mage is in direct sunlight, they have damage weakness 3. While the dusk mage has concealment, they have damage immunity 3.

---

## Shadow Elf Assassin
*Level 6 Platoon Artillery*
*Keywords: Fey, Humanoid, Shadow Elf*
*EV 16*

| Stat | Value |
|------|-------|
| Size | 1M |
| Speed | 5 |
| Stamina | 70 |
| Stability | 0 |
| Free Strike | 7 |

**Immunities:** --
**Weaknesses:** --
**Movement Modifiers:** Climb

| MGT | AGL | REA | INU | PRS |
|-----|-----|-----|-----|-----|
| 0 | +3 | +2 | +1 | +1 |

### Lumina Assault (2d10 + 3)
*Signature Ability*
*Ranged, Strike, Weapon*
*Main action*
*Ranged 15 | One creature or object*

- **Tier 1 (<=11):** 10 damage
- **Tier 2 (12-16):** 15 damage
- **Tier 3 (17+):** 18 damage

**Effect:** The next ability used against the target has a double edge. 5 Malice: Each non-minion ally within 3 squares of the target can make a free strike against them.

### Splitbow (2d10 + 3)
*2 Malice*
*Area, Ranged, Weapon*
*Main action*
*4 x 1 line within 10 | Each enemy in the area*

- **Tier 1 (<=11):** 5 damage; I<1 bleeding (save ends)
- **Tier 2 (12-16):** 10 damage; I<2 bleeding (save ends)
- **Tier 3 (17+):** 12 damage; I<3 bleeding (save ends)

**Effect:** Each target is pushed up to 4 squares.

### Trait: Of the Umbra
The assassin ignores concealment created by darkness. While the assassin is in direct sunlight, they have damage weakness 3. While the assassin has concealment, they have damage immunity 3.

---

## Shadow Elf Duskcaller
*Level 5 Platoon Controller*
*Keywords: Fey, Humanoid, Shadow Elf*
*EV 14*

| Stat | Value |
|------|-------|
| Size | 1M |
| Speed | 5 |
| Stamina | 60 |
| Stability | 0 |
| Free Strike | 6 |

**Immunities:** --
**Weaknesses:** --
**Movement Modifiers:** Climb

| MGT | AGL | REA | INU | PRS |
|-----|-----|-----|-----|-----|
| 0 | +3 | +3 | +2 | +1 |

### Night Knife (2d10 + 3)
*Signature Ability*
*Melee, Strike, Weapon*
*Main action*
*Melee 1 | One creature or object*

- **Tier 1 (<=11):** 9 damage
- **Tier 2 (12-16):** 13 damage
- **Tier 3 (17+):** 16 damage

**Effect:** If the duskcaller has concealment, they can target one additional creature or object.

### The Lay of Cor'thoroth
*Area, Magic, Ranged*
*Maneuver*
*2 cube within 3 | Special*

**Effect:** Until the start of the duskcaller's next turn, the area is filled with darkness. 2 Malice: The size of the cube increases by 3.

### Trait: Of the Umbra
The duskcaller ignores concealment created by darkness. While the duskcaller is in direct sunlight, they have damage weakness 3. While the duskcaller has concealment, they have damage immunity 3.

---

## Shadow Elf Knightfell
*Level 4 Platoon Defender*
*Keywords: Fey, Humanoid, Shadow Elf*
*EV 12*

| Stat | Value |
|------|-------|
| Size | 1M |
| Speed | 5 |
| Stamina | 70 |
| Stability | 0 |
| Free Strike | 5 |

**Immunities:** --
**Weaknesses:** --
**Movement Modifiers:** Climb

| MGT | AGL | REA | INU | PRS |
|-----|-----|-----|-----|-----|
| 0 | +2 | 0 | +3 | +2 |

### Suffusing Strike (2d10 + 3)
*Signature Ability*
*Magic, Ranged, Strike*
*Main action*
*Ranged 3 | One creature or object*

- **Tier 1 (<=11):** 8 corruption damage
- **Tier 2 (12-16):** 12 corruption damage; R<2 taunted (EoT)
- **Tier 3 (17+):** 15 corruption damage; R<3 taunted (EoT)

### Trick of the Eye
*Magic, Melee*
*Triggered action*
*Melee 2 | One ally*

**Trigger:** An enemy within distance makes a strike against the target.

**Effect:** The target takes half the damage and the knightfell takes the other half.

### Trait: Of the Umbra
The knightfell ignores concealment created by darkness. While the knightfell is in direct sunlight, they have damage weakness 3. While the knightfell has concealment, they have damage immunity 3.

---

## Shadow Elf Moondancer
*Level 5 Platoon Harrier*
*Keywords: Fey, Humanoid, Shadow Elf*
*EV 14*

| Stat | Value |
|------|-------|
| Size | 1M |
| Speed | 7 |
| Stamina | 70 |
| Stability | 0 |
| Free Strike | 6 |

**Immunities:** --
**Weaknesses:** --
**Movement Modifiers:** Climb

| MGT | AGL | REA | INU | PRS |
|-----|-----|-----|-----|-----|
| +1 | +3 | +1 | +2 | 0 |

### Crescent Sweep (2d10 + 3)
*Signature Ability*
*Charge, Melee, Strike, Weapon*
*Main action*
*Melee 1 | One creature or object*

- **Tier 1 (<=11):** 9 damage
- **Tier 2 (12-16):** 13 damage
- **Tier 3 (17+):** 16 damage

**Effect:** Until the end of the current turn, the moondancer ignores opportunity attacks from the target.

### Dissolve
*Magic*
*Triggered action*
*Self | Self*

**Trigger:** The moondancer takes damage from a strike.

**Effect:** The moondancer can teleport up to 10 squares to a space with concealment created by darkness.

### Trait: Of the Umbra
The moondancer ignores concealment created by darkness. While the moondancer is in direct sunlight, they have damage weakness 3. While the moondancer has concealment, they have damage immunity 3.

---

## Shadow Elf Mournblade
*Level 6 Platoon Ambusher*
*Keywords: Fey, Humanoid, Shadow Elf*
*EV 16*

| Stat | Value |
|------|-------|
| Size | 1M |
| Speed | 5 |
| Stamina | 80 |
| Stability | 0 |
| Free Strike | 7 |

**Immunities:** --
**Weaknesses:** --
**Movement Modifiers:** Climb

| MGT | AGL | REA | INU | PRS |
|-----|-----|-----|-----|-----|
| +2 | +3 | +1 | +2 | 0 |

### Knife in the Dark (2d10 + 3)
*Signature Ability*
*Melee, Strike, Weapon*
*Main action*
*Melee 1 | One creature or object*

- **Tier 1 (<=11):** 10 damage
- **Tier 2 (12-16):** 15 damage
- **Tier 3 (17+):** 18 damage

**Effect:** The mournblade is invisible to the target until the start of the mournblade's next turn.

### Shadow Step
*Magic*
*Maneuver*
*Self | Self*

**Effect:** If the mournblade has concealment, they can teleport up to 10 squares to a space with concealment created by darkness.

### Trait: Of the Umbra
The mournblade ignores concealment created by darkness. While the mournblade is in direct sunlight, they have damage weakness 3. While the mournblade has concealment, they have damage immunity 3.

---

## Shadow Elf Luminator
*Level 4 Platoon Support*
*Keywords: Fey, Humanoid, Shadow Elf*
*EV 12*

| Stat | Value |
|------|-------|
| Size | 1M |
| Speed | 5 |
| Stamina | 60 |
| Stability | 0 |
| Free Strike | 5 |

**Immunities:** --
**Weaknesses:** --
**Movement Modifiers:** Climb

| MGT | AGL | REA | INU | PRS |
|-----|-----|-----|-----|-----|
| 0 | +1 | +1 | +3 | +2 |

### Lumina Mark (2d10 + 3)
*Signature Ability*
*Magic, Ranged, Strike*
*Main action*
*Ranged 3 | One creature or object*

- **Tier 1 (<=11):** 8 lightning damage
- **Tier 2 (12-16):** 12 lightning damage
- **Tier 3 (17+):** 15 lightning damage

**Effect:** The next strike made against the target deals an extra 5 damage.

### Mourning Till Dusk (2d10 + 3)
*3 Malice*
*Area, Magic*
*Main action*
*2 burst | Each ally in the area*

- **Tier 1 (<=11):** The target regains 6 Stamina.
- **Tier 2 (12-16):** The target regains 9 Stamina.
- **Tier 3 (17+):** The target regains 12 Stamina and the Director gains 3 Malice.

**Effect:** Each target gains an edge on their next strike.

### Trait: Of the Umbra
The luminator ignores concealment created by darkness. While the luminator is in direct sunlight, they have damage weakness 3. While the luminator has concealment, they have damage immunity 3.

---

## Shadow Elf Noctis Mage
*Level 6 Platoon Hexer*
*Keywords: Fey, Humanoid, Shadow Elf*
*EV 16*

| Stat | Value |
|------|-------|
| Size | 1M |
| Speed | 5 |
| Stamina | 70 |
| Stability | 0 |
| Free Strike | 6 |

**Immunities:** --
**Weaknesses:** --
**Movement Modifiers:** Climb

| MGT | AGL | REA | INU | PRS |
|-----|-----|-----|-----|-----|
| 0 | +2 | +3 | +1 | +1 |

### Blotting Bolt (2d10 + 3)
*Signature Ability*
*Magic, Ranged, Strike*
*Main action*
*Ranged 5 | One creature or object*

- **Tier 1 (<=11):** 9 damage
- **Tier 2 (12-16):** 14 damage
- **Tier 3 (17+):** 17 damage

**Effect:** The target takes a bane on their next strike. 3 Malice: The target instead has a double bane on the next ability they use.

### Enemies in the Dark (2d10 + 3)
*3 Malice*
*Magic, Ranged, Strike*
*Main action*
*Ranged 5 | Two enemies*

- **Tier 1 (<=11):** 8 damage; R<1 the target makes a free strike against one enemy of the noctis mage's choice.
- **Tier 2 (12-16):** 10 damage; R<2 the target makes a free strike against one enemy of the noctis mage's choice.
- **Tier 3 (17+):** 13 damage; R<3 the target uses a signature ability against one enemy of the noctis mage's choice.

### Trait: Of the Umbra
The noctis mage ignores concealment created by darkness. While the noctis mage is in direct sunlight, they have damage weakness 3. While the noctis mage has concealment, they have damage immunity 3.

---

## Shadow Elf Panther
*Level 4 Platoon Brute*
*Keywords: Fey, Humanoid, Shadow Elf*
*EV 12*

| Stat | Value |
|------|-------|
| Size | 1M |
| Speed | 5 |
| Stamina | 70 |
| Stability | 0 |
| Free Strike | 6 |

**Immunities:** --
**Weaknesses:** --
**Movement Modifiers:** Climb

| MGT | AGL | REA | INU | PRS |
|-----|-----|-----|-----|-----|
| +3 | +2 | -1 | +1 | +1 |

### Dusk Cleave (2d10 + 3)
*Signature Ability*
*Melee, Strike, Weapon*
*Main action*
*Melee 1 | One creature or object*

- **Tier 1 (<=11):** 9 damage
- **Tier 2 (12-16):** 13 damage
- **Tier 3 (17+):** 16 damage; I<3 bleeding (save ends)

**Effect:** The panther can make a free strike against a creature or object adjacent to the target.

### Bladestorm (2d10 + 3)
*3 Malice*
*Area, Weapon*
*Main action*
*2 burst | Each enemy in the area*

- **Tier 1 (<=11):** 5 corruption damage
- **Tier 2 (12-16):** 8 corruption damage; I<2 dazed (save ends)
- **Tier 3 (17+):** 10 corruption damage; I<3 dazed (save ends)

**Effect:** The panther has a double edge on strikes against targets dazed this way.

### Trait: Of the Umbra
The panther ignores concealment created by darkness. While the panther is in direct sunlight, they have damage weakness 3. While the panther has concealment, they have damage immunity 3.

---

## Shadow Elf Eclipse
*Level 6 Leader*
*Keywords: Fey, Humanoid, Shadow Elf*
*EV 32*

| Stat | Value |
|------|-------|
| Size | 1M |
| Speed | 6 |
| Stamina | 180 |
| Stability | 1 |
| Free Strike | 7 |

**Immunities:** --
**Weaknesses:** --
**Movement Modifiers:** Climb

| MGT | AGL | REA | INU | PRS |
|-----|-----|-----|-----|-----|
| +4 | +3 | +2 | +1 | +2 |

### Manifold Blade (2d10 + 4)
*Signature Ability*
*Melee, Strike, Weapon*
*Main action*
*Melee 1 | Two creatures or objects*

- **Tier 1 (<=11):** 11 damage; I<2 bleeding (save ends)
- **Tier 2 (12-16):** 16 damage; I<3 bleeding (save ends)
- **Tier 3 (17+):** 19 damage; I<4 bleeding (save ends)

2 Malice: The potency increases by 1.

### Grasping Shadow (2d10 + 4)
*Magic, Ranged*
*Maneuver*
*Ranged 5 | Three creatures or objects casting a shadow*

- **Tier 1 (<=11):** Pull 5; I<2 slowed (save ends)
- **Tier 2 (12-16):** Pull 7; I<3 slowed (save ends)
- **Tier 3 (17+):** Pull 10; I<4 slowed (save ends)

### Put It Out!
*Ranged*
*Triggered action*
*Ranged 10 | The triggering enemy*

**Trigger:** An enemy within distance uses an ability that emits light, including abilities that deal fire or lightning damage.

**Effect:** The target has a double bane on the ability.

### Trait: End Effect
At the end of each of their turns, the eclipse can take 10 damage to end one effect on them that can be ended by a saving throw. This damage can't be reduced in any way.

### Trait: Of the Umbra
The eclipse ignores concealment created by darkness. While the eclipse is in direct sunlight, they have damage weakness 3. While the eclipse has concealment, they have damage immunity 3.

### From the Shadows (Villain Action 1)
*Ranged*
*Ranged 5 | Special*

**Effect:** The eclipse calls forth one brush stalker into an unoccupied space within distance. Each ally within distance can then shift up to their speed and make a free strike.

### Cast Away All Hope (Villain Action 2)
*Area, Magic*
*3 burst | Each enemy in the area*

**Effect:** Each target loses all their surges. Additionally, until the end of the round, allies ignore edges and double edges on any targets' abilities, and ignore any nondamaging effects of any target's damage-dealing abilities.

### Umbral Hunger (Villain Action 3, 2d10 + 4)
*Area, Magic*
*3 cube within 5 | Each enemy in the area*

- **Tier 1 (<=11):** 7 corruption damage; R<2 the target has speed 0 (save ends)
- **Tier 2 (12-16):** 12 corruption damage; R<3 the target has speed 0 (save ends)
- **Tier 3 (17+):** 15 corruption damage; R<4 the target has speed 0 (save ends)

**Effect:** The area is shrouded in darkness that creates concealment until the end of the encounter. Any enemy who starts their turn in the area takes 5 corruption damage.

---

## Brush Stalker
*Level 4 Platoon Mount*
*Keywords: Animal, Fey, Shadow Elf*
*EV 12*

| Stat | Value |
|------|-------|
| Size | 2 |
| Speed | 8 |
| Stamina | 60 |
| Stability | 3 |
| Free Strike | 5 |

**Immunities:** --
**Weaknesses:** --
**Movement Modifiers:** --

| MGT | AGL | REA | INU | PRS |
|-----|-----|-----|-----|-----|
| +3 | +2 | -1 | +1 | +1 |

### Gore (2d10 + 3)
*Signature Ability*
*Charge, Melee, Strike, Weapon*
*Main action*
*Melee 2 | Two creatures or objects*

- **Tier 1 (<=11):** 7 damage
- **Tier 2 (12-16):** 10 damage
- **Tier 3 (17+):** 13 damage

### Reclamation (2d10 + 3)
*2 Malice*
*Area, Magic*
*Main action*
*2 burst | Each enemy in the area*

- **Tier 1 (<=11):** 4 corruption damage; M<1 weakened (save ends)
- **Tier 2 (12-16):** 7 corruption damage; M<2 weakened (save ends)
- **Tier 3 (17+):** 10 corruption damage; M<3 weakened (save ends)

### Trait: Suneater
The area within 2 squares of the brush stalker is devoid of light and provides concealment.

### Trait: Wyrd Dyr
While they have line of effect to the brush stalker, any animal except another brush stalker is frightened.


---

## Shadow Elf Shade
*Level 4 Ambusher Retainer*
*Keywords: Fey, Humanoid, Shadow Elf*

| Stat | Value |
|------|-------|
| Size | 1M |
| Speed | 5 |
| Stamina | 48 |
| Stability | 0 |
| Free Strike | 5 |

**Immunities:** --
**Weaknesses:** --
**Movement Modifiers:** Climb

| MGT | AGL | REA | INU | PRS |
|-----|-----|-----|-----|-----|
| +1 | +3 | 0 | +2 | +1 |

### Gloom Dagger (2d10 + highest characteristic)
*Signature Ability*
*Melee, Ranged, Strike, Weapon*
*Main action*
*Melee 1 or ranged 3 | One creature or object*

- **Tier 1 (<=11):** 6 damage
- **Tier 2 (12-16):** 10 damage
- **Tier 3 (17+):** 13 damage

**Effect:** Whenever the shade starts their turn with concealment from the target, they gain 1 surge.

### Duskfall
*Encounter*
*Area, Magic*
*Maneuver*
*3 cube within 1 | Special*

**Effect:** Until the end of the next turn, the area is filled with darkness. The shade's mentor ignores concealment created by this darkness.

### Trait: Of the Umbra
The shade ignores concealment created by darkness. While the shade is in direct sunlight, they have damage weakness 3. While the shade has concealment, they have damage immunity 3.

### Slow-Poison Needle (2d10 + highest characteristic) -- Level 7 Advancement
*Encounter*
*Ranged, Strike, Weapon*
*Main action*
*Ranged 5 | One creature*

- **Tier 1 (<=11):** 8 poison damage; weakened (save ends)
- **Tier 2 (12-16):** 12 poison damage; weakened (save ends)
- **Tier 3 (17+):** 16 poison damage; weakened (save ends)

**Effect:** The slow-poison needle is initially painless, with the damage and effect delayed until the start of the target's next turn. If the shade is hidden, using this ability doesn't cause them to be revealed.

### Shadow Dagger (2d10 + highest characteristic) -- Level 10 Advancement
*Encounter*
*Melee, Strike, Weapon*
*Main action*
*Melee 1 | One creature*

- **Tier 1 (<=11):** 12 poison damage; the target has shadowed vision (save ends)
- **Tier 2 (12-16):** 17 poison damage; the target has shadowed vision (save ends)
- **Tier 3 (17+):** 23 poison damage; the target has shadowed vision (save ends)

**Effect:** While a creature has shadowed vision, all creatures have concealment from them.
