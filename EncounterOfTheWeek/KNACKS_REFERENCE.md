# Knacks: hero-specific options in montages and journal tests

A **knack** is anything about one hero that changes a test: a language, a
movement mode, an immunity, an ancestry trait, a class or subclass feature, an
ability (Black Ash Teleport), a perk, a complication, a career, a culture, a
kit, a deity, an item they carry, their Wealth or Renown.

Authors write the **intent** ("you can teleport"). The code works out which
heroes qualify, from every rule that grants it: a teleport speed, Black Ash
Teleport, Practical Magic's teleport, and anything added later. Script text
never names pregens.

Code: `DMHub Game Rules/TestRiders.lua` (the grammar, the
vocabulary, `CreatureFacts`). The montage parts are in
`EncounterOfTheWeek/` (`EncounterScript.lua`,
`EncounterMontage.lua`, `EncounterMontageStage.lua`). Tests are in
`tests/encounter_script_test.lua`.

**Companions** (montages only, 2026-10-08). A hero who approaches an
entry may take companions along. Their knack versions (`#### If ...`),
secret options (`Allow` lines) and languages (garbled speech, `PC speaks
X`) count for the turn, credited as "..., thanks to Mira". **Edge and bane
riders, and the other scene conditions, read only the hero making the
test**, so a companion's weakness never puts a bane on the roll -- and a
companion's language does not earn an `Edge: you speak X` either. Write a
language that should help as a knack version or a secret option if a
companion should be able to supply it.

## 1. The four ways a knack shows up

### Edge / bane riders

A rider line goes in a test's power-roll block, after its tiers:

```
|Climbing Test: Might or Agility (Climb, Endurance)
|You lose a recovery.
|You lose a recovery. The threat is vanquished.
|The threat is vanquished.
|Edge: you can climb or fly
|Bane: you have cold weakness
```

- **Effects:** `Edge`, `Double Edge`, `Bane`, `Double Bane`.
- **Limited to one round:** `|Edge (Round 1): ...`.
- **In the roll dialog:** each rider becomes a pre-ticked chip whose name
  includes the source, e.g. "Edge: you can teleport (Black Ash Teleport)".

### Secret options

An option with an `Allow` line is **secret**: a hero who does not meet the
requirement never sees it. The other spellings of `Allow` are `Secret`,
`Only`, `Requires` and `Required`.

```
### Ask the stones the way

PC lays a hand on a mossy stone and listens to it.

|The old stones remember the dwarven road. The threat is vanquished.
|Allow: you are a Dwarf
```

- Everyone watches the hero standing at the entry. So a secret option appears
  for the other players at the same moment it appears for the player who is
  choosing, and stays hidden whenever that hero does not qualify.
- A secret option's outcome icons are left off the shared entry card.
- In a **journal** power roll, an `Allow` line still shows the roll locked,
  with "Requires: ...".

### Options with no roll

A `###` option whose `|` lines are clauses, with no `|Name: Characteristic`
header, is taken **without a test**. Its clauses apply at once.

- Lines above the rules are the option's own scene.
- Lines below the rules are its outcome scene.
- A rider line here can only be `Allow`/`Secret`. Edges have no roll to apply
  to, and the validator warns about them.

### Knack versions: `#### If <requirement>`

A `####` heading under an option starts an **alternative version** of that
option, for a hero who meets the requirement. It can do one of two things.

It can remove the roll:

```
### Find another crossing
|Crossing Test: Agility (Swim, Sneak, Navigate)
|... three tiers ...
|Edge: you can swim or fly

#### If you can teleport

PC: Hold this end of the rope.

|You blink across the ford and haul the others over on the rope. The threat is vanquished.
```

Or it can give the hero a better power table:

```
#### If you can teleport
|Blink Test: Agility (Sneak, Gymnastics)
|A clumsy landing => +1 malice. The threat is vanquished.
|Silenced => The threat is vanquished.
|Gone before he blinks => The threat is vanquished. +1 hero token.
```

- **Heading forms:** `#### If <req>`, `#### Instead, if <req>:` and
  `#### Knack: <req>`. `If PC can fly` reads the same as `If you can fly`.
- **Which version a hero gets:** the first knack they meet. It is fixed when
  they choose the option.
- **What the hero sees:** a violet card with "Knack: you can teleport (Black
  Ash Teleport)", and "no roll" beside the option's name for a no-roll
  version.
- **Scenes:** the option's own pre-roll lines play first, then the knack's.
  The knack's outcome lines play if it has any. A rolled knack with no outcome
  lines of its own reuses the option's.
- **Riders:** a knack's roll does **not** inherit the base roll's edges. The
  option's `Allow` lines still decide who may take the option at all.
- **Montage log:** records "Knack: <why>".

### Scene conditions

Scene conditions accept the same vocabulary:

- `if PC can fly then`
- `if PC has the Monster Whisperer perk then`
- `if PC is immune to fire then`
- `if PC was a Farmer then`
- `if PC carries a lantern then`
- `if PC worships Grole the One-Handed then`

`PC has X` now means anything the hero has by that name: a skill, perk,
ability, trait, item and so on. Use `PC is skilled in X` for skills only.

## 2. The requirement vocabulary

A requirement is a list of alternatives joined by `or`, commas or
semicolons. A bare name inherits the previous kind: `you are skilled in
Magic, Alchemy or Psionics`, `you have the Ritualist perk, Lucky Dog or
Brawny`.

`N or higher` / `N or more` fold into one threshold, and so do `N or lower` /
`N or less`. Because "or" separates alternatives, **no capability phrase may
contain the word "or"**. A test enforces this.

| Kind | Write | Met by |
|---|---|---|
| skill | `you are skilled in Track`, `you have the Track skill` | proficiency |
| language | `you speak Zaliac` | languages known (Mindspeech included) |
| kindred | `you are a Dwarf` / `a Shadow` / `a Black Ash`... | class, subclass, ancestry (with "Elf, High" = "high elf"), and career |
| capability | `you can teleport` (table below) | movement speeds, ability behaviours, immunities, named features |
| anything by name | `you have Black Ash Teleport` | any skill, trait, ability, perk, complication, kit, title, item, career, deity, domain of that name |
| perk | `you have the Lucky Dog perk` | the hero's chosen perks |
| complication | `you have the Frostheart complication` | complications |
| ability | `you can use Black Ash Teleport`, `you have the X ability` | activated abilities, or a trait of that name |
| trait | `you have the Stone Singer trait` / `feature` | any class, ancestry, career, culture, kit or complication feature |
| career | `you were a Farmer`, `your career is Soldier` | the career |
| culture | `you were raised in the Wilderness`, `you come from an Urban culture` | culture name and aspects |
| kit | `your kit is Mountain`, `you use the Panther kit` | kit (both of a Tactician's) |
| deity | `you worship Grole the One-Handed` | the deity choice |
| domain | `you serve the Life domain` | the chosen domains and the domain subclasses |
| title | `you hold the Knight title` | titles |
| item | `you carry a Healing Potion`, `you carry the Bastion Belt` | inventory and equipped items (plural tolerated) |
| immunity | `you are immune to fire`, `you have fire immunity` | any immunity to that damage type |
| weakness | `you have fire weakness`, `you are weak to fire` | any weakness to that type (good for banes) |
| condition immunity | `you cannot be surprised`, `you can't be frightened` | condition immunities. "Surprised" also counts Danger Sense, Primordial Cunning and Unphased |
| size | `you are tiny` / `small` / `large` / `huge`, `your size is 1L or larger` | Draw Steel size order 1T < 1S < 1M < 1L < 2 ... |
| numbers | `your Wealth is 2 or higher`, `your Renown is 2 or higher`, `you are level 2 or higher`, `you have 3 or more victories`, `your Might is 2 or higher`, `your Might is 0 or lower` | Wealth, Renown, Level, Victories, the five characteristics |

### Capabilities

| Capability (`you can ...`) | Also accepts | Met by |
|---|---|---|
| teleport | | a teleport speed, or any ability that moves you by teleport (read from the ability's behaviours: Black Ash Teleport, Practical Magic, Heart of the Beast...) |
| fly | | a fly speed (Wings), Corven kit |
| climb | | a climb speed at least your speed, Raden kit, Sewer Folk |
| swim | | a swim speed, Waterborn, Sewer Folk |
| burrow | | a burrow speed |
| speak with animals | talk to animals, talk to plants... | Green elementalist, Stormwight, Raised by Beasts, Voice of the Wild |
| handle monsters | calm monsters, soothe beasts | Monster Whisperer, or anyone who can speak with animals |
| talk to the dead | speak with spirits... | Grave Speech, Dead Men Tell All Tales, Medium, Bereaved |
| sense the supernatural | detect magic, sense undead... | Detect the Supernatural, A Beyonding of Vision, Runic Carving, Heart of Nature, Creature Sense, Soulsense |
| use telepathy | read minds, read thoughts... | Mindspeech, Telepathic Speech, Runic Carving, Psychic Whisper, Prisoner of the Synlirii, Telepathy talent |
| shape stone | shape earth, work stone... | Stone Singer, Motivate Earth, Earth elementalist, Grounded |
| make light | shed light, light the way... | Runic Carving, Fire elementalist, Sun domain, Arcane Trick |
| make fire | start a fire... | Return to Formlessness, Fire elementalist |
| melt objects | burn objects, melt metal... | Return to Formlessness |
| see in the dark | see in darkness | Hellsight |
| see the invisible | see through illusions, see through walls | A Beyonding of Vision, Beyondsight |
| shapeshift | change shape, become an animal | Aspect of the Wild, Stormwight, Animal Form |
| go unnoticed | pass unseen, hide in plain sight, become a shadow... | Wode Elf Glamor, Shadowmeld, Shadow, Forgettable Face, Master of Disguise, Camouflage Hunter, I'm No Threat, Smoke Bomb, Silent Sentinel |
| disguise yourself | wear a disguise, change your face | Forgettable Face, Master of Disguise, I'm No Threat, Stolen Face |
| move things with your mind | use telekinesis | Invisible Force, Telekinesis talent, Minor Telekinesis |
| work minor magic | use magic, cast a cantrip | Arcane Trick, Practical Magic, Elementalist |
| perform a blessing | bless, perform a ritual | Ritualist, Conduit, Censor |
| heal others | heal, tend wounds | Healing Grace, My Life for Yours, Conduit |
| endure the cold | resist cold, brave the cold | any cold immunity, Wilds Explorer |
| endure heat | resist fire, walk through fire | any fire immunity, Wilds Explorer |
| endure poison | resist poison, endure disease | any poison immunity |
| brave the wilds | brave the elements, cross rough terrain | Wilds Explorer, Danger Sense, Forest Walk, Nimblestep |
| breathe underwater | breathe water | Waterborn, Tough But Withered |
| sense danger | sense an ambush, sense traps | Danger Sense, High Senses, Foresight, Doomsight |
| lift great weights | lift heavy things, break things apart | All Is a Feather, Big!, Hakaan, Berserker, Brawny |
| leap great distances | jump far, leap | Mighty Leaps, Lightning Leap, Fury |
| fall safely | survive a fall, land safely | Fall Lightly, I've Got You!, a fly speed, Wings |
| decipher writing | read any language, read maps... | Linguist, Systematic Mind, Blessing of Comprehension, Knowledge domain |
| change the weather | control the weather | Blessing of Fortunate Weather, Storm domain |
| create objects | conjure tools | Hands of the Maker, Improvisation Creation |
| disarm traps | jam traps | Gum Up the Works |
| escape bonds | slip free | Slipped Lead |

**Adding a capability.** Call `TestRiders.RegisterCapability{ key, phrases,
describe, movement, tag, immunity, sources }`. A plain source name matches
any trait, ability, perk, complication, kit or item. A `kind:name` source
matches only that kind (`kindred:green`, `perk:monster whisperer`,
`language:mindspeech`). Add a source here whenever new content grants an
existing intent. Old scripts then pick it up with no edit.

**Possible next step.** Move the source lists into the compendium, as a
`capabilities` tag list on `CharacterFeature`, so new content declares its own
intents.

## 3. Perks the montage plays by their real rules

These need no authoring. They work in every montage.

| Perk / feature | In a montage |
|---|---|
| Brawny | A failed (tier 1) Might test: the hero is offered "lose 1d6 + level Stamina, raise one tier". |
| Lucky Dog | The same, for a test that lists an intrigue skill. |
| Put Your Back Into It! | An assist that rolls tier 1 imposes no bane. Once per montage, the perk's owner is offered "turn an ally's tier 1 into tier 2" (inside a delve, only a companion of the delving hero). |
| Pardon My Friend | When the hero fails (tier 1) a Presence test, a companion with the perk may make the test instead, with a bane: Presence + their own skill, edges and perks, on the test's table. Their roll replaces the hero's. Once per test. |
| Team Leader | In round 1, before anyone acts: spend a hero token, and every hero tests (and assists) as if they had the leader's exploration skills. |
| Teamwork | Everyone may now approach AND go along each round, so Teamwork lets the hero go along with two approaches in round 1. |
| Ritualist | Once a round, bless the test of the hero at an entry: your own, or the hero you are accompanying (the ritual needs a touch). A double edge. A button appears for the Ritualist's player while the hero chooses. |
| Born Tracker | An edge on a test that lists Track or Navigate. |
| Polymath / Handy | +1 on a lore / crafting test when the hero has none of the listed skills. |
| Power Player | Might may stand in for the listed characteristic on a Brag, Flirt or Intimidate test. |
| Mighty Leaps (Fury) | A Might test that lists Jump never lands below tier 2. |
| any skill-scoped feature edge | The montage roll now passes the test's skills to the modifier query. So Wode Elf Glamor (Sneak), High Elf Glamor (Persuade), Perseverance (Endurance), Four-Armed Athletics and the like apply exactly as on a sheet-rolled skill test. |

Perk offers time out after 30 seconds.

**Not yet implemented:**
- Wood Wise (needs a reroll inside the dice dialog).
- Area of Expertise and Specialist (they need the perk's chosen skill).
- Charming Liar.

## 4. The authoring standard

- **Every test** carries 1-2 knack riders. Make one *broad* (at least one
  pregen meets it) and one optionally a *deep cut* (an immunity, a
  complication, a rare ancestry trait).
- **Every opportunity** has 1-2 secret options or knack versions, at least
  one reachable by a pregen.
- **About half the threats** have a secret option or knack, usually the
  "trivialize" kind: no roll, a tier-2-sized result (vanquished, no hero
  token), so it reads as "of course you can".
- **Every hero** of the week's pregen party meets 3 or more knacks across the
  montage, and no one requirement carries the montage.
- **Drawbacks as banes** are cheap and make complications feel real (Revenant
  fire weakness, cold weakness). Use about one per montage, and never on a
  required threat.

### Choosing how strong a knack is

| Rung | Use when |
|---|---|
| A line in the scene | It colours the scene, nothing more |
| Edge | The knack helps |
| Double edge | The knack is exactly what the task needs (a Dwarf reading dwarven runes) |
| Secret option, rolled | The hero has a different approach |
| Knack version, better table | Same approach, easier for this hero |
| Secret option / knack version, no roll | The knack makes the problem moot |

**Checking it.** The Encounter Script validator (`/eotwvalidate`) has a
**Knack coverage** section. It lists:
- tests with no knack,
- opportunities with no secret option or knack,
- threats with one,
- any requirement over 15% of the montage's hooks,
- a per-hero table for a party you pick. The default is the largest party,
  which in an authoring game is the week's pregens.

The pregens are only a breadth test. Nothing in the code knows them by name.
