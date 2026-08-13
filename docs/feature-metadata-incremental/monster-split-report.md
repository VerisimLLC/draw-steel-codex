# Monster Split Sweep -- one book item, multiple data objects

Sweep date: 2026-08-13, per James+David: every monster statblock item
(trait or ability) must be ONE self-contained object in data -- an ability
that works when copied alone, or one feature carrying everything (text,
activated ability, triggers) under the book item's name. This report finds
the violations. Analysis only -- nothing has been changed.

Method: parsed every unhidden monster in data/monsters/ (604) and matched
430 to Book Two statblocks in monster-reference.md by name. For each book
item, counted the data objects covering it (standalone innate abilities +
features matching by name or by the ability they grant). Also flagged
'orphan' mechanical features whose name matches NO book item (trigger/
power/aura/modifyability carriers -- the Cackletongue Trigger shape),
with a token-overlap guess at which book item they support. Stat carriers
(immunities, Hover, free-strike types, summon costs) are excluded --
those are the Hidden-tag population, not splits.

## Results: 45 split items across 40 monsters, plus 75 orphan support features

### Pattern A: book item covered by standalone ability AND a same-name feature
The dominant shape (triggered actions implemented twice: the ability on
the sheet plus a feature holding the working trigger).

- **Aeolyxria the Uncanny** -- 'Elevate': standalone ability, standalone ability  `(aeolyxria-the-uncanny.yaml)`
- **Ajax the Invincible** -- 'Tactical Stance': standalone ability, feature 'Tactical Stance'  `(ajax-the-invincible.yaml)`
- **Ajax the Invincible (Leader)** -- 'Tactical Stance': standalone ability, feature 'Tactical Stance'  `(ajax-the-invincible-leader.yaml)`
- **Angulotl Daybringer** -- 'Tongue Slap': standalone ability, feature 'Tongue Slap'  `(angulotl-daybringer.yaml)`
- **Bugbear Channeler** -- 'Catcher': standalone ability, feature 'Catcher'  `(bugbear-channeler.yaml)`
- **Bugbear Roughneck** -- 'Catcher': standalone ability, feature 'Catcher'  `(bugbear-roughneck.yaml)`
- **Bugbear Roughneck** -- 'Flying Sawblade': standalone ability, feature 'Flying Sawblade'  `(bugbear-roughneck.yaml)`
- **Chimera** -- 'Ram's Defiance': standalone ability, feature 'Ram's Defiance'  `(chimera.yaml)`
- **Demon Chimeron** -- 'Lethe': feature 'Lethe', feature 'Lethe'  `(demon-chimeron.yaml)`
- **Demon Chimeron** -- 'Soulsight': feature 'Soulsight', feature 'Soulsight'  `(demon-chimeron.yaml)`
- **Demon Vicisitator** -- 'Soulsight': feature 'Soulsight', feature 'Soulsight'  `(demon-vicisitator.yaml)`
- **Fossil Cryptic** -- 'Dissipate': standalone ability, feature 'Dissipate'  `(fossil-cryptic.yaml)`
- **Fossil Cryptic** -- 'Shatterstone': standalone ability, feature 'Shatterstone'  `(fossil-cryptic.yaml)`
- **Giant Zombie** -- 'Knocking Heads': standalone ability, feature 'Knocking Heads'  `(giant-zombie.yaml)`
- **Goblin Monarch** -- 'Meat Shield': standalone ability, feature 'Meat Shield'  `(goblin-monarch.yaml)`
- **High Elf Ordinator** -- 'Enough!': standalone ability, feature 'Enough!'  `(high-elf-ordinator.yaml)`
- **Hobgoblin Incendiarist** -- 'Fireball Volley': standalone ability, standalone ability  `(hobgoblin-incendiarist.yaml)`
- **Human Brawler** -- 'Shoot the Hostage': standalone ability, feature 'Shoot the Hostage'  `(human-brawler.yaml)`
- **Lithgekh** -- 'Devour Magic': standalone ability, feature 'Devour Magic'  `(lithgekh.yaml)`
- **Lithgekh** -- 'Mystic Battery': standalone ability, feature 'Mystic Battery'  `(lithgekh.yaml)`
- **Lumbering Egress** -- 'Abyssal Protectors': standalone ability, feature 'Abyssal Protectors'  `(lumbering-egress.yaml)`
- **Medusa** -- 'Venomous Spit': standalone ability, feature 'Venomous Spit'  `(medusa.yaml)`
- **Ogre Goon** -- 'Swat the Fly': standalone ability, feature 'Swat the Fly'  `(ogre-goon.yaml)`
- **Ogre Juggernaut** -- 'Defiant Anger': feature 'Defiant Anger', feature 'Defiant Anger'  `(ogre-juggernaut.yaml)`
- **Olothec** -- 'Liquify': standalone ability, feature 'Liquify'  `(olothec.yaml)`
- **Orc Rampart** -- 'No.': standalone ability, feature 'No'  `(orc-rampart.yaml)`
- **Orc Razor** -- 'Boot and Blade': standalone ability, feature 'Boot and Blade'  `(orc-razor.yaml)`
- **Radenwight Mischiever** -- 'Ready Rodent': standalone ability, feature 'Ready Rodent'  `(radenwight-mischiever.yaml)`
- **Radenwight Ratcrobat** -- 'Ready Rodent': standalone ability, feature 'Ready Rodent'  `(radenwight-ratcrobat.yaml)`
- **Radenwight Redeye** -- 'Eyes-On-Me-Shot': standalone ability, standalone ability  `(radenwight-redeye.yaml)`
- **Radenwight Redeye** -- 'Ready Rodent': standalone ability, feature 'Ready Rodent'  `(radenwight-redeye.yaml)`
- **Radenwight Swiftpaw** -- 'Ready Rodent': standalone ability, feature 'Ready Rodent'  `(radenwight-swiftpaw.yaml)`
- **Relentless Tusker Demon** -- 'Vengeful Tusker': standalone ability, feature 'Vengeful Tusker'  `(2d2c1179-5609-4ec0-b47b-a7798de524e8.yaml)`
- **Shadow Elf Moondancer** -- 'Dissolve': standalone ability, feature 'Dissolve'  `(shadow-elf-moondancer.yaml)`
- **Shadow Elf Panther** -- 'Bladestorm': standalone ability, feature 'Bladestorm'  `(shadow-elf-panther.yaml)`
- **Shambling Mound** -- 'Tether Down': standalone ability, feature 'Tether Down'  `(shambling-mound.yaml)`
- **Trained Gummy Brick** -- 'You Didn't Pay Attention!': standalone ability, feature 'You Didn’t Pay Attention!'  `(trained-gummy-brick.yaml)`
- **Troll Glutton** -- 'Spiteful Retort': standalone ability, feature 'Spiteful Retort'  `(troll-glutton.yaml)`
- **Tusker Demon** -- 'Vengeful Tusker': standalone ability, feature 'Vengeful Tusker'  `(tusker-demon.yaml)`
- **War Dog Amalgamite** -- 'Several Arms': standalone ability, feature 'Several Arms'  `(war-dog-amalgamite.yaml)`
- **War Dog Breaker** -- 'Loyalty Collar': feature 'Loyalty Collar', feature 'Loyalty Collar'  `(war-dog-breaker.yaml)`
- **War Spider** -- 'Skitter': standalone ability, feature 'Skitter'  `(war-spider.yaml)`
- **Wode Elf Green Seer** -- 'Foreseen Punishment': standalone ability, feature 'Foreseen Punishment'  `(wode-elf-green-seer.yaml)`
- **Wode Elf Yeoman** -- 'Masking Glamor': feature 'Masking Glamor', feature 'Masking Glamor'  `(wode-elf-yeoman.yaml)`
- **Wode Hag** -- 'Turned Upside Down': standalone ability, feature 'Turned Upside Down'  `(wode-hag.yaml)`

### Pattern B: orphan support features (no book item with that name)
The Gnoll Cackletongue shape: the working trigger lives in a feature a
cloner would never know to copy. 'likely supports' is a token-overlap
guess; None = no guess, needs a human eye.

- **Accursed Mummy** -- feature 'Mummy Dust' (beh: trigger, triggerdisplay) -> likely supports: Blast of Mummy Dust  `(0c1c3e78-fbd0-4f1e-9f62-fc8450f0e200.yaml)` - This is a trait on a summoner minion
- **Ajax the Invincible** -- feature 'Ajax' (beh: attribute, resource, trigger) -> likely supports: Ajax Turns  `(ajax-the-invincible.yaml)` - This is a trait and everything it needs is inside it. 
- **Ajax the Invincible (Leader)** -- feature 'Ajax' (beh: attribute, trigger) -> likely supports: Ajax Turns  `(ajax-the-invincible-leader.yaml)` 
- **Big Animal A** -- feature 'Nature Calls' (beh: trigger) -> likely supports: Nature's Spirit  `(big-animal-a.yaml)`
- **Big Animal B** -- feature 'Nature Calls' (beh: trigger) -> likely supports: Nature's Spirit  `(big-animal-b.yaml)`
- **Elemental Mote** -- feature 'Dweomer Burst' (beh: trigger) -> likely supports: Dweomer Plume  `(0544e196-72af-45a7-845d-0aabbe177bdb.yaml)`
- **Ensnarer** -- feature 'Extended Barbed Strike' (beh: modifyability) -> likely supports: Barbed Tongues  `(6617b9db-7b48-4946-9076-8cd4c238e9b5.yaml)`
- **Gloom Dragon** -- feature 'Gloom Dragon's Domain' (beh: aura, monstermodes) -> likely supports: Gloom Dragon Malice  `(gloom-dragon.yaml)`
- **Gnoll Abyssal Archer** -- feature 'Cackletongue Trigger' (beh: trigger) -> likely supports: Archer's Cackletongue  `(gnoll-abyssal-archer.yaml)`
- **Gnoll Abyssal Summoner** -- feature 'Cackletongue Trigger' (beh: trigger) -> likely supports: Summoner's Cackletongue  `(gnoll-abyssal-summoner.yaml)`
- **Gnoll Bonesplitter** -- feature 'Cackletongue Trigger' (beh: trigger) -> likely supports: Bonesplitter's Cackletongue  `(gnoll-bonesplitter.yaml)`
- **Gnoll Cackler** -- feature 'Cackletongue Trigger' (beh: trigger) -> likely supports: Cackler's Cackletongue  `(gnoll-cackler.yaml)`
- **Gnoll Carnage** -- feature 'Cackletongue Trigger' (beh: trigger) -> likely supports: Carnage's Cackletongue  `(gnoll-carnage.yaml)`
- **Gnoll Marauder** -- feature 'Cackletongue Trigger' (beh: trigger) -> likely supports: Marauder's Cackletongue  `(gnoll-marauder.yaml)`
- **Lightbender Pouncer** -- feature 'Stalker's AfterImage' (beh: powertabletrigger, trigger) -> likely supports: Striking Afterimage  `(lightbender-pouncer.yaml)`
- **Orc Juggernaut** -- feature 'Haymaker Greataxe Prone Bonus Damage' (beh: power) -> likely supports: Haymaker Greataxe  `(orc-juggernaut.yaml)`
- **Orc Rampart** -- feature 'My Spear, My Foe Bonus' (beh: trigger) -> likely supports: My Spear, My Foe  `(orc-rampart.yaml)`
- **Predator A** -- feature 'Nature Calls' (beh: trigger) -> likely supports: Nature's Spirit  `(predator-a-duplicate.yaml)`
- **Rival Shadow** -- feature 'Exploit Opening' (beh: power) -> likely supports: Exploit Weakness  `(rival-shadow.yaml)`
- **Shadow Elf Mournblade** -- feature 'Knife in the Dark Cleanup' (beh: trigger) -> likely supports: Knife in the Dark  `(shadow-elf-mournblade.yaml)`
- **Stalker Shade** -- feature 'Shadow Strike' (beh: trigger) -> likely supports: Shadow Phasing  `(dc6a13fd-ec77-4a06-8514-95d127287c71.yaml)`
- **Thorn Dragon** -- feature 'Thorny Scales' (beh: trigger, triggerdisplay) -> likely supports: Thorn Dragon Malice  `(thorn-dragon.yaml)`
- **Wode Elf Greenskeeper** -- feature 'Hunter's Glamor' (beh: trigger, triggerdisplay) -> likely supports: Masking Glamor  `(wode-elf-greenskeeper.yaml)`
- **Wode Elf Warleader** -- feature 'Hunter's Glamor' (beh: trigger, triggerdisplay) -> likely supports: Masking Glamor  `(wode-elf-warleader.yaml)`
- **Xorannox the Tyract** -- feature 'Solo Monster' (beh: trigger) -> likely supports: Solo Monster -- End Effect  `(xorannox-the-tyract.yaml)`
- **Zombie Lumberer** -- feature 'Zombie Clutch' (beh: modifyability, trigger) -> likely supports: Clobber and Clutch  `(edf6be40-04f5-4b65-8120-d936df9370c2.yaml)`
- **Arixx** -- feature 'End Effect' (beh: trigger) -> likely supports: UNKNOWN - needs review  `(arixx-0faee81e.yaml)`
- **Basilisk** -- feature 'Venomous' (beh: trigger) -> likely supports: UNKNOWN - needs review  `(basilisk.yaml)`
- **Basilisk Companion** -- feature 'Foes Forever Frozen' (beh: power) -> likely supports: UNKNOWN - needs review  `(basilisk-companion.yaml)`
- **Bugbear Snare** -- feature 'Determine if Bugbear hidden' (beh: trigger) -> likely supports: UNKNOWN - needs review  `(bugbear-snare.yaml)`
- **False Vampire** -- feature 'Proboscis Strike' (beh: modifyability) -> likely supports: UNKNOWN - needs review  `(7d243ece-10d4-45c5-807a-9877b19a242f.yaml)`
- **Fire Giant Chief** -- feature 'End Effect' (beh: trigger) -> likely supports: UNKNOWN - needs review  `(fire-giant-chief.yaml)`
- **Fossil Cryptic** -- feature 'End Effect' (beh: trigger) -> likely supports: UNKNOWN - needs review  `(fossil-cryptic.yaml)`
- **Gloom Dragon Illusion** -- feature 'Illusion' (beh: resource, trigger) -> likely supports: UNKNOWN - needs review  `(gloom-dragon-illusion.yaml)`
- **High Elf Ordinator** -- feature 'Magic Beacon' (beh: aura) -> likely supports: UNKNOWN - needs review  `(high-elf-ordinator.yaml)`
- **Hollowbone Launcher** -- feature 'Arise' (beh: trigger) -> likely supports: UNKNOWN - needs review  `(hollowbone-launcher.yaml)`
- **Lightbender Companion** -- feature 'Hit and Run' (beh: trigger) -> likely supports: UNKNOWN - needs review  `(lightbender-companion.yaml)`
- **Lightbender Companion** -- feature 'Everywhere and Nowhere' (beh: activated, modsummoner, power) -> likely supports: UNKNOWN - needs review  `(lightbender-companion.yaml)`
- **Lithgekh** -- feature 'Arise' (beh: trigger) -> likely supports: UNKNOWN - needs review  `(lithgekh.yaml)`
- **Orc Chainlock** -- feature 'Bloodfire Burn' (beh: trigger) -> likely supports: UNKNOWN - needs review  `(orc-chainlock.yaml)`
- **Phase Ghoul** -- feature 'Leaping Strike' (beh: modifyability) -> likely supports: UNKNOWN - needs review  `(4a1425d8-cc6b-4498-b5a3-3b5ee86f0d38.yaml)`
- **Rival Conduit** -- feature 'Stalwart Guardian' (beh: aura) -> likely supports: UNKNOWN - needs review  `(rival-conduit.yaml)`
- **Rival Conduit E2** -- feature 'Stalwart Guardian' (beh: aura) -> likely supports: UNKNOWN - needs review  `(rival-conduit-e2.yaml)`
- **Rival Elementalist** -- feature 'Jaws of the Void' (beh: trigger, triggerdisplay) -> likely supports: UNKNOWN - needs review  `(rival-elementalist-fdd2231c.yaml)`
- **Rival Elementalist E2** -- feature 'Fissures of Darkness' (beh: trigger, triggerdisplay) -> likely supports: UNKNOWN - needs review  `(rival-elementalist-e2.yaml)`
- **Rival Elementalist E3** -- feature 'Maw of the Abyss' (beh: trigger, triggerdisplay) -> likely supports: UNKNOWN - needs review  `(rival-elementalist-e3.yaml)`
- **Rival Fury** -- feature 'Overwhelm' (beh: trigger, triggerdisplay) -> likely supports: UNKNOWN - needs review  `(rival-fury.yaml)`
- **Rival Fury** -- feature 'Let's Tussle' (beh: power) -> likely supports: UNKNOWN - needs review  `(rival-fury.yaml)`
- **Rival Fury E2** -- feature 'Overpower' (beh: trigger, triggerdisplay) -> likely supports: UNKNOWN - needs review  `(rival-fury-e2.yaml)`
- **Rival Fury E3** -- feature 'Rout' (beh: trigger, triggerdisplay) -> likely supports: UNKNOWN - needs review  `(rival-fury-e3.yaml)`
- **Rival Null** -- feature 'Inertial Shield' (beh: powertabletrigger) -> likely supports: UNKNOWN - needs review  `(rival-null-6d75af8d.yaml)`
- **Rival Null E2** -- feature 'Inertial Shield' (beh: powertabletrigger) -> likely supports: UNKNOWN - needs review  `(rival-null-e2.yaml)`
- **Rival Null E3** -- feature 'Force Dampener' (beh: powertabletrigger) -> likely supports: UNKNOWN - needs review  `(rival-null-e3.yaml)`
- **Rival Tactician** -- feature 'Overwatch' (beh: trigger) -> likely supports: UNKNOWN - needs review  `(rival-tactician.yaml)`
- **Rival Tactician E2** -- feature 'Take the Opening' (beh: trigger) -> likely supports: UNKNOWN - needs review  `(rival-tactician-e2.yaml)`
- **Rival Tactician E3** -- feature 'Quickshot' (beh: trigger) -> likely supports: UNKNOWN - needs review  `(rival-tactician-e3.yaml)`
- **Rival Talent** -- feature 'Precognitive Shift' (beh: powertabletrigger) -> likely supports: UNKNOWN - needs review  `(rival-talent.yaml)`
- **Rival Talent E2** -- feature 'Precognitive Shift' (beh: powertabletrigger) -> likely supports: UNKNOWN - needs review  `(rival-talent-e2.yaml)`
- **Rival Talent E2** -- feature 'Precognitive Shift' (beh: powertabletrigger, trigger) -> likely supports: UNKNOWN - needs review  `(rival-talent-e2.yaml)`
- **Rival Talent E3** -- feature 'Mind Requital' (beh: powertabletrigger, trigger) -> likely supports: UNKNOWN - needs review  `(rival-talent-e3.yaml)`
- **Shambling Mound** -- feature 'Alchemical Ingredients' (beh: trigger) -> likely supports: UNKNOWN - needs review  `(shambling-mound.yaml)`
- **Skeleton** -- feature 'Bonetrops' (beh: trigger) -> likely supports: UNKNOWN - needs review  `(45bc13b2-8863-4120-8cb3-0202f828c525.yaml)`
- **Soulraker Hivequeen** -- feature 'Lethe' (beh: power) -> likely supports: UNKNOWN - needs review  `(soulraker-hivequeen.yaml)`
- **Soulraker Stinger** -- feature 'Lethe' (beh: power) -> likely supports: UNKNOWN - needs review  `(soulraker-stinger.yaml)`
- **Thorn Dragon** -- feature 'End Effect' (beh: trigger) -> likely supports: UNKNOWN - needs review  `(thorn-dragon.yaml)`
- **Troll Limbjumble duplicate** -- feature 'Lingering Hunger' (beh: trigger) -> likely supports: UNKNOWN - needs review  `(troll-limbjumble-duplicate.yaml)`
- **Werewolf** -- feature 'End Effect' (beh: trigger) -> likely supports: UNKNOWN - needs review  `(werewolf.yaml)`
- **Werewolf** -- feature 'Holy Damage Taken' (beh: trigger) -> likely supports: UNKNOWN - needs review  `(werewolf.yaml)`
- **Wode Hag** -- feature 'End Effect' (beh: trigger) -> likely supports: UNKNOWN - needs review  `(wode-hag.yaml)`
- **Zombie Lumberer** -- feature 'Death Grasp' (beh: attribute, trigger) -> likely supports: UNKNOWN - needs review  `(edf6be40-04f5-4b65-8120-d936df9370c2.yaml)`
- **Zombie Mine** -- feature 'Proximity Detonation' (beh: aura) -> likely supports: UNKNOWN - needs review  `(zombie-mine.yaml)`
- **Zombie Mine** -- feature 'Explosive Demise' (beh: trigger) -> likely supports: UNKNOWN - needs review  `(zombie-mine.yaml)`
- **Zombie Titan** -- feature 'Big Stomp' (beh: modifyability) -> likely supports: UNKNOWN - needs review  `(cb312674-6d16-49d7-8b94-eaefbad21da4.yaml)`
- **Zombie Titan** -- feature 'Overwhelming Size' (beh: attribute, trigger) -> likely supports: UNKNOWN - needs review  `(cb312674-6d16-49d7-8b94-eaefbad21da4.yaml)`
- **Zombie Titan** -- feature 'Flesh to Mountains' (beh: trigger, triggerdisplay) -> likely supports: UNKNOWN - needs review  `(cb312674-6d16-49d7-8b94-eaefbad21da4.yaml)`

## Pattern A taxonomy: what the standalone abilities actually are

Question (James 2026-08-13): are the standalone abilities generated by the
trigger modifier's manual-version option, or separately created? Answer:
**separately authored/imported.** The engine's real mechanism for a manual
card is `hasManualVersion` on the TriggeredAbility
(TriggeredAbility.lua:578 `GenerateManualVersion`, surfaced by
MCDMCreature.lua:3160 when building the ability list) -- that card is a
runtime clone (`_tmp_temporaryClone`) and is NEVER serialized. Anything in
`innateActivatedAbilities` in the YAML was put there by the importer or a
human. Engine-wide usage: 53 monster feature triggers use
`hasManualVersion: true`, 37 explicit false, 467 unset -- so the proper
mechanism exists but the standalone-ability workaround predates/outnumbers
it.

The 45 split items break down as:

| Shape | n | What it is | Clone failure |
|---|---|---|---|
| Parallel duplicate logic | 23 | ability carries its own copy of the effect behaviors AND the feature's trigger carries a second copy | either half alone half-works; copies desync on edit |
| Display-card ability | 9 | ability has ZERO behaviors -- pure text card; feature does everything | stealing the ability gives a dead card |
| Invoke-linked | 4 | feature trigger invokes the standalone ability BY NAME (`abilityType: named`) | stealing the feature alone silently invokes nothing; renaming the ability breaks it |
| Double standalone ability | 3 | same item twice in innateActivatedAbilities | likely import/authoring duplicates -- check identical, dedupe |
| Double feature | 6 | same item twice in characterFeatures | same |

**Double-card bonus defect**: 6 pairs ALSO set `hasManualVersion: true` on
the feature trigger while a standalone ability exists, so the card can
appear twice: Ajax Tactical Stance (both variants), Bugbear
Channeler/Roughneck Catcher, Radenwight Ratcrobat Ready Rodent, Trained
Gummy Brick "You Didn't Pay Attention!".

### Examples to eyeball

- **Parallel duplicate** -- Ogre Goon "Swat the Fly"
  (data/monsters/ogre-goon.yaml): standalone ability at :528 carries
  `ActivatedAbilityDrawSteelCommandBehavior rule: Slide 5`; the feature at
  :130 carries a triggerdisplay plus a `leaveadjacentorshift` trigger whose
  triggeredAbility contains ANOTHER `DrawSteelCommandBehavior` copy. Two
  implementations of the same slide.
- **Display-card** -- War Spider "Skitter"
  (data/monsters/war-spider.yaml:442 ability, :609 feature): the ability
  has `behaviors: []`, description text only; the feature's
  powertabletrigger does the movement.
- **Invoke-linked** -- Ajax "Tactical Stance"
  (data/monsters/ajax-the-invincible.yaml:157 feature, :188 ability): the
  feature's beginround trigger contains
  `ActivatedAbilityInvokeAbilityBehavior { abilityType: named,
  namedAbility: "Tactical Stance" }` -- a runtime name reference to the
  standalone ability.
- **Double-card** -- Radenwight Ratcrobat "Ready Rodent"
  (data/monsters/radenwight-ratcrobat.yaml): standalone triggered-action
  ability AND `hasManualVersion: true` on the feature trigger.

### Implication for the merge design (not yet actioned)

All of shapes 1-3 converge on one target form: a single feature named after
the book item carrying the activated modifier (the manual/display card) and
the trigger modifier, with the trigger invoking the contained ability
rather than duplicating behaviors -- or, where a card adds nothing, one
feature whose trigger sets `hasManualVersion: true` and no separate ability
at all. Engine question to verify first: named invoke + hasManualVersion
resolution for feature-granted (vs innate) abilities. Doubles are
dedupe-deletes after an identical-content check.

## Addendum 2026-08-13 (later): completeness answer + structural re-sweep

James asked whether the 45 are exhaustive. Answer: they were the complete
set for the 430 Book-Two-matched monsters at sweep time -- not a sample --
but the same-name pair check needs no book, so it was re-run STRUCTURALLY
across ALL 604 unhidden monsters (including adventure content: Delian Tomb,
Red Road, Condemned, etc.). Hidden monsters excluded by design (not in
bestiary, should not reach the builder).

Current count after James's first fixes landed in the data repo
(commits e87a547 skitter dedupe, 1ace271 tactical stance merge, 5ff9066
ready rodent consolidation): **52 same-name pairs/doubles remain.**
New finds outside the Book Two set:

- Vassa'sellak -- Embody the Blood Drinker (ability + feature)
- Nixie Soakreed -- Water Weird (ability + feature)
- Sudden Downpour -- See Through (ability + feature)
- Tomb Horror -- Ruinous Grasp (ability + feature)
- Radenwight Ratagast -- Ready Rodent (ability + feature)
- Rival Fury -- Let's Tussle (ability + feature)
- Rival Shadow (scratch duplicate) -- Envenomed Steel (ability + feature)
- Archdevil -- True Name (2x feature)
- Fossil Cryptic -- Solo Turn (2x feature)
- Soulraker Stinger -- Soulsight (2x feature)

Still open from the original list: the remaining Ready Rodents
(Mischiever, Redeye, Swiftpaw), Ajax the Invincible (Leader) Tactical
Stance, and everything not yet touched. James's merged form is the
template: Ogre Goon's Swat the Fly feature now carries
triggerdisplay + trigger + activated ability in ONE feature (verified in
data). Origin note confirmed by James: behavior-less duplicates are import
artifacts; behavior-carrying standalones were added deliberately because
the trigger's manual-version option cannot target (it hits the caster
instead of the triggering creature) -- fixing that engine limitation would
remove the reason these keep being authored.

The orphan-support-feature list (Pattern B) still only covers Book Two
monsters -- adventure monsters cannot be orphan-checked without their own
references and need a manual pass or their adventure docs.

### Progress -- James's consolidation pass (updated 2026-08-13 EOD)

**PATTERN A: FINISHED** except two stragglers James could not locate,
verified still present by structural re-sweep:

1. Radenwight Ratagast -- Ready Rodent (ability + feature). File
   radenwight-ratagast.yaml, bestiary folder "Radenwight". NOTE: the
   ability name carries a trailing space ("Ready Rodent ").
2. "Rival Shadow duplicate duplicate" -- Envenomed Steel (ability +
   feature). Folder Rival -> ECHELON 4. Three scratch copies of Rival
   Shadow exist (duplicate / dup-dup / dup-dup-dup); only this one has the
   pair. Candidate for deletion rather than repair.

**PATTERN B (orphan support features): NOT STARTED.** James continues
content work 2026-08-14.

Earlier progress detail (superseded, kept for history):

DONE (data commits e87a547..e807e3e): everything alphabetically through
**Shambling Mound**, plus the double-standalone-ability trio (Aeolyxria
Elevate, Hobgoblin Incendiarist Fireball Volley, Radenwight Redeye
Eyes-On-Me-Shot) and War Spider Skitter. Verified by structural re-sweep
against current data.

REMAINING (19):

| Monster | Item | Shape |
|---|---|---|
| Olothec | Liquify | ability + feature (alphabetically before Shambling Mound -- possibly skipped, please check) |
| Trained Gummy Brick | You Didn't Pay Attention! | ability + feature |
| Troll Glutton | Spiteful Retort | ability + feature |
| Tusker Demon | Vengeful Tusker | ability + feature |
| War Dog Amalgamite | Several Arms | ability + feature |
| Wode Elf Green Seer | Foreseen Punishment | ability + feature |
| Wode Hag | Turned Upside Down | ability + feature |
| Nixie Soakreed | Water Weird | ability + feature (non-Book-Two) |
| Radenwight Ratagast | Ready Rodent | ability + feature (non-Book-Two) |
| Rival Fury | Let's Tussle | ability + feature |
| Rival Shadow (scratch dup) | Envenomed Steel | ability + feature |
| Sudden Downpour | See Through | ability + feature |
| Tomb Horror | Ruinous Grasp | ability + feature |
| Vassa'sellak | Embody the Blood Drinker | ability + feature |
| Archdevil | True Name | 2x feature |
| Rival Talent E2 | Precognitive Shift | 2x feature |
| Soulraker Stinger | Soulsight | 2x feature |
| War Dog Breaker | Loyalty Collar | 2x feature |
| Wode Elf Yeoman | Masking Glamor | 2x feature |

Pattern B orphans (Cackletongue shape) not yet started.

## Not checked

174 unhidden data monsters had no Book Two match:
companions/summons (Bear, drakes...), Summoner/Beastheart-book creatures,
adventure/homebrew monsters (Cradle set, Dame Cornelia, Guest Star...),
and a few name variants. The same invariant applies to them, but there is
no book reference to diff against; they need the same one-object check
during their own content pass. Full list in the JSON alongside this file.
