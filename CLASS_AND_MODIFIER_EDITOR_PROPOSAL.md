# Class and Modifier Editors: applying the Ability Blocks approach

**Status:** PROPOSAL, 2026-11-21. Nothing here is decided. No Lua or engine code was changed.
Builds on [`ABILITY_BLOCKS_DESIGN.md`](ABILITY_BLOCKS_DESIGN.md) (the brief) and its prototype
[`ui-mockup/ability-blocks-stack.html`](ui-mockup/ability-blocks-stack.html).

**Evidence base.** Counts come from `draw-steel-data` (`objectTables/` and `monsters/`, 4,260 files
parsed; 2 rival monster files fail to parse because of a tab). Code references are to this repo.
The book text is `ClaudeBridge/ClaudeRefHeroes.lua` (Shadow chapter, pages 175-190).

---

## 0. Recommendations in one screen

1. **Build the modifier sentences first, then the class page.** A class feature is a list of
   modifiers, so the modifier sentences are the vocabulary both editors share (and the ability
   editor already needs them for "While this ability resolves" and ongoing effects).
2. **Route four modifier types to the editor that already exists.** `activated`, `trigger`,
   `powertabletrigger` and `triggerdisplay` (3,133 of 8,023 modifiers, 39%) open the simplified
   ability/trigger editor. The modifier editor only has to own the other 61%.
3. **Eleven more sentences cover 97% of all modifiers.** Modify Attribute and Modify Power Rolls
   alone are 41%; everything else is an Advanced block that saves untouched.
4. **One "applies when" sentence replaces three conditions.** Power roll modifiers have
   `filterCondition`, `displayCondition` and `activationCondition` (plus `activationAfterRoll`);
   authors describe "Always / You choose when you roll / Only if ...", the editor picks fields.
5. **The class editor shows a class the way the book prints it:** Basics, heroic resource,
   then "Nth-Level Features" with each feature as name + text + ("You have the following ability"
   + card). The preview generates the book's Advancement table from the data.
6. **Authors say "at 1st level"; the editor decides the storage** (`tutoriallevel-1..4` vs
   `level-1`), as it decides Multiple Modes vs Ability Variations today.
7. **Heroic resource gain is one sentence that writes two linked records** (the class checklist
   entry and the trigger whose Replenish step points to it by `checklistid`; 69 such links exist).
8. **Opening is safe by the same rule:** unchanged saves byte-identical; changed blocks write over
   their original record; hidden fields (`domains`, `guid`, `sourceReference`, `imported`,
   `importOverride`, `implementation`, `tags`) ride along. Gate: 70/70 classes and 8,023/8,023
   modifiers round-trip before any editing ships.
9. **Paste reuses existing importers:** `DrawSteelRulesImporter.lua` (plain-text classes and
   kits) for class pages; the ability paste reader for granted abilities.
10. **Content findings come out of the same scripts** (Section 5): five different implementations
   of "Characteristic Increase", modifiers that copy the feature text (1,040 of 1,765), abilities
   matched by name, and three records still pointing at 5e `armorClass`.

---

## 1. What carries over from the ability editor

| Ability editor rule (brief, Section 7) | Class editor | Modifier editor |
|---|---|---|
| Read mode: sentences with underlined words; click one word to edit it | Feature and Basics lines | Every modifier is one sentence |
| Shelf right of the stack, organised by intent, ordered by usage, "Common" band + compact categories + one search | Feature shelf (Section 3.2) | Modifier shelf (Section 4.2) |
| "+" moves the gold marker; the shelf is the one place to choose | Between features and inside a level | Inside a feature, effect, kit... |
| Author describes; editor chooses storage | Level 1 placement, feature shapes, resource gains | Attribute operations, power roll conditions, trigger types |
| Book first: saved wording wins; generated text uses book phrasing | Feature description and the class page | Owner's text wins; modifier sentence is the automation summary |
| Unchanged saves identical; Advanced blocks carry what blocks don't model | Same | Same |
| GoblinScript hidden behind test/value blocks; "Show GoblinScript" | 735 real formulas in class records | 720 non-empty `filterCondition`s |
| Paste text + teach loop | Rules importer | Feature/trait text to modifier sentences |
| Simpler editor beside the old one, never replacing it | `DSClassEditor.lua` stays | `CharacterModifier` forms stay as Settings |

---

## 2. Evidence at a glance

**Where modifiers live** (8,023 `CharacterModifier` records): monsters 2,743, classes and subclasses
2,068, ongoing effects 1,504, gear 362, creature templates 277, complications 208, titles 168,
ancestries 138, condition riders 118, kits 73, others under 75.

**Behaviour usage** (45 of 62 registered types appear; 11 are deregistered for Draw Steel in
`MCDMRules.lua:1729-1739`):

| # | Behaviour (editor name) | Uses | Cum. | Classes | Monsters | Route |
|---|---|---|---|---|---|---|
| 1 | `attribute` (Modify Attribute) | 1,854 | 23% | 401 | 736 | Sentence |
| 2 | `trigger` (Triggered Ability) | 1,573 | 43% | 291 | 698 | Trigger editor |
| 3 | `power` (Modify Power Rolls) | 1,392 | 60% | 235 | 396 | Sentence |
| 4 | `activated` (Activated Ability) | 1,052 | 73% | 643 | 101 | Ability editor |
| 5 | `resistance` (Damage Immunity) | 383 | 78% | 44 | 144 | Sentence |
| 6 | `triggerdisplay` | 354 | 82% | 124 | 183 | Retired into trigger card (brief 4j) |
| 7 | `modifyability` (Modify Abilities) | 309 | 86% | 77 | 103 | Sentence |
| 8 | `aura` | 202 | 89% | 30 | 91 | Sentence (reuses Create Aura block) |
| 9 | `powertabletrigger` | 154 | 91% | 54 | 66 | Trigger editor |
| 10 | `movementtext` (Reminder Text) | 89 | 92% | 3 | 36 | Sentence |
| 11 | `modsummoner` | 71 | 93% | 7 | 63 | Advanced |
| 12 | `resource` (Grant Resource) | 65 | 94% | 34 | 3 | Sentence |
| 13 | `conditionimmunity` | 65 | 94% | 6 | 28 | Sentence |
| 14 | `proficiency` (Skill or Language) | 64 | 95% | 34 | 0 | Sentence |
| 15 | `bestowcondition` | 63 | 96% | 1 | 16 | Sentence |
| 16 | `suppressabilities` | 57 | 97% | 3 | 7 | Sentence |
| | 29 others (loyaltycollar 41, modcompanion 33, transform 23, modifytrigger 19, ... 1 each) | 241 | 100% | | | Advanced |

**Class structure** (70 Class records: 8 classes, 3 classes with `isSubclass` unset (Censor, Null,
Troubadour), 59 subclasses of which 14 are hidden duplicate domain records in `classes/`):

| Node | Count | Notes |
|---|---|---|
| `CharacterFeature` | 1,337 | 601 hold only ability grants (596 exactly one); 159 one attribute change; 139 have no modifiers (text only) |
| `CharacterFeatureChoice` | 210 | 168 are "pick 1 of 2" or "1 of 4"; 130 offer only abilities |
| `CharacterFeatureList` | 163 | Mostly Characteristic Increase (fixed raise + choice) |
| `CharacterSkillChoice` | 88 | |
| `CharacterFeatChoice` | 54 | Editor calls it "Choice of a Feat"; all 54 are named **Perk** |
| `CharacterSubclassChoice` | 12 | |
| Deity / Companion choices | 2 / 1 | |
| Nesting depth | 870 at 1, 765 at 2, 232 at 3 | Choice > list > feature is common |

---

## 3. The Class editor

### 3.1 What authors struggle with today

Today's editor (`Draw Steel UI/DSClassEditor.lua`, `Draw Steel Core Rules/MCDMClass.lua`) is a
form: class fields, then a "Tutorial" section with Encounter 1-4 cards, then Level 1-10 cards. Each
card is an "Add Features..." dropdown (Single Feature, Multiple Features, Choice, Choice of a Feat,
Specific Feat, Subclass, registered choices, prefabs, Paste) and nested feature forms, each with
an "Add Modifier" picker and one form per modifier.

1. **Level 1 is not where the book puts it.** Level-1 features live under *Tutorial > Encounter
   1-4* (`tutoriallevel-1..4`, the slow-start progression in `Class:FillLevelsUpTo`). 46 records put
   features there, but 8 put them in `level-1` (Censor and Conduit "1st-Level Domain Feature",
   Troubadour "Scene Partner", Caustic Alchemy "Smoke Bomb", the three psionic disciples' skills).
   Every record also carries empty 5e keys (`primary`, `multiclass`) and 6 carry empty
   `level-11..20`.
2. **Most features are wrappers.** 601 features (45%) exist only to hold an ability; 296 of them
   have no description, so the sheet falls back to the ability's flavor (`CharacterFeature:GetDescription`).
   The book says "You have the following ability." and prints the card.
3. **The same book sentence is implemented many ways.** "Characteristic Increase" (22+ copies):
   Fury uses `max 3` for "increases to 3" and `set 5` at 10th; Tactician uses `add 1` for "increases
   to 3" (correct only because the base is 2); "each increases by 1, to a maximum of 4" is `add 1`
   with no `cap`; Elementalist uses `add 1, cap 5` plus a `min 5` (a no-op below 5; worth checking).
4. **Rules live away from the text that states them.** Shadow's 4th-level *Surge of Insight* ("you
   gain 2 insight instead of 1") is a feature with no modifiers; the rule is a Level-keyed table
   (1/2/3) on the class's resource checklist. The *Insight* feature is five modifiers (three
   triggers, a resource, an attribute) and each repeats the full feature text: across classes,
   **1,040 of 1,765 modifiers copy their feature's description**.
5. **The heroic resource is stored twice.** The class's `heroicResourceChecklist` (33 records; 149
   formula quantities, e.g. `GoblinScriptTable` by Level) is the player's checklist; triggers with a
   Replenish step automate the same gains and link back by `checklistid` (69 links). Authors must
   create both and wire the guid by hand.
6. **GoblinScript where a number would do.** 735 real formulas in class records:
   `conditionFormula` 184, `value` 158, checklist `quantity` 149, `filterCondition` 99,
   `displayCondition` 52, `activationCondition` 38, subclass `prerequisite` 22 (all
   `Deity.Domains has "X"`), `hitpointsCalculation` 11 (all `A + (Level - 1)*B`, the book's two
   numbers). Choice size `numChoices` is a GoblinScript box whose help example is 5e
   (`Max(1, Intelligence Modifier)`); content only uses 1 or 2.
7. **Levelled improvements have three storages.** Later-level upgrades are written as a separate
   feature with `abilityimprovement` (10) or `modifyability` (40 in classes), as `Level >= N` in a
   formula (23), or as a Level-keyed `GoblinScriptTable` (22). The book always prints them as a
   feature at the new level ("Careful Observation Improvement", 7th).
8. **Book words versus editor words.** Perk vs "Choice of a Feat"; Heroic Ability choice vs
   "Choice"; "Multiple Features" for what the book shows as one feature with two effects.

### 3.2 The blocks

The page is one stack in the book's order, beside a live **class page preview**:

```
Shadow                                             [Paste class text]
  Basics
    You start with an [Agility] of [2]; choose an array from [2,2,-1,-1] [2,1,1,-1] ...
    Starting Stamina at 1st level [18]; gained at 2nd and higher levels [6]
    Recoveries [8]
    You have the [Hide] and [Sneak] skills; choose [five] from [Criminal Underworld, exploration...]
    Kit: you can use and gain the benefits of [a martial kit]
  Insight (heroic resource)                          icon [..]  epic resource [Subterfuge]
    At the start of combat, you gain insight equal to [your Victories]
    At the start of each of your turns, you gain [1d3] insight
    The first time each round you [deal damage with a surge], you gain [1] insight
    ...
  1st-Level Features
    Shadow College: choose your [subclass]
    Signature Ability: choose [one] of  [Gasping in Pain] [I Work Better Alone] [...]   (+)
  4th-Level Features
    Characteristic Increase: your [Agility] increases to [3]; increase one other by 1, to a maximum of [3]
    Keep It Down                                    narrative
    Night Watch: While you are hidden, enemies take a bane on ... (aura)
                 You have the following ability: [Night Watch card]  -> trigger editor
    Perk   Skill   Surge of Insight: you gain [2] insight instead of [1]  (improves Insight)
```

**Feature shelf**, organised by intent, ordered by usage in class records:

| Group | Block (sentence) | Uses | Saves as | First-class? |
|---|---|---|---|---|
| Abilities | You have the following ability: [card] | 601 features | Feature + `activated` | Common |
| | Choose [one] [signature / N-resource heroic] ability from: | 130 choices | Choice of single-ability features | Common |
| | You have the following triggered ability | ~220 features with a trigger or power roll trigger | Feature + trigger types | Common |
| Choices | Choose [one] of: (options are any blocks) | 80 other choices | `CharacterFeatureChoice` | Common |
| | Perk / Skill / Language | 54 / 88 / prefab | registered choices | Common |
| | Your [subclass] / deity / domain / companion | 12 / 2 / 1 | registered choices | Common |
| Characteristics | Characteristic Increase (fixed raise + choice) | 22+ lists | List of attribute features + choice | Common |
| Rules | Any modifier sentence (Section 4) | 159 attribute-only, 42 power, 31 proficiency, 23 modify ability, 15 resistance, 12 aura ... | Modifiers on this feature | Common for the top 6 |
| Text | Narrative feature (no automation) | 139 | Feature with description only, `implementation: 0` | Common |
| Improvements | Improves [earlier feature]: [what changes] | 10 + 40 + 45 | See 3.4 | First-class |
| Kits | Kit access [martial / caster], two kits | 9 + 3 | `kitaccess`, `numKits` | Basics line |
| Advanced | Prefabs, specific feat, former-life choice, points-cost choices | 22, rare | as stored | Advanced |

Feature metadata that authors rarely touch (implementation status: 628 fully, 531 mostly, 89
partly, 25 narrative, 9 not automated, 55 unset; tags such as Ability 496, Combat 339, Hidden 220)
goes under each feature's Settings, with the status also shown as a quiet badge.

### 3.3 Book first

The book's class chapter has a fixed shape (Shadow, pp. 175-190): intro and quote; **Basics**
(starting characteristics and arrays, weak/average/strong potency, starting Stamina and Stamina per
level, Recoveries, skills with a Quick Build); **1st-Level Features** with the subclass choice and
its options; the **Advancement table** (Level | Features | Abilities | Subclass Abilities, e.g.
"4th | Characteristic Increase, Keep It Down, Night Watch, Perk, Skill, Surge of Insight | Signature,
3, 5, 7 | 5"); the **resource** section ("Insight in Combat", "Insight Outside of Combat"); then
"Nth-Level Features", each a heading, paragraphs and "You have the following ability." with a card.
Subclass features are shown as tables ("1st-Level College Features: Black Ash | Black Ash Teleport").

The preview is that page, generated from the data:
- Feature text is the saved `description` (book wording wins). A feature with none shows the book
  phrase "You have the following ability." plus the ability card (the same card renderer as the
  ability editor), or "Add feature text" rather than invented wording.
- The **Advancement table is generated** from the levels (feature names per level, ability cost
  columns from the choices' categories), so authors check structure at a glance, and the poll
  script can compare it with the book's table.
- Resource names follow the class (Insight, Wrath, Piety): already decided for ability costs.
- Each line links to its `sourceReference` page (1,197 features carry one).
- Modifier sentences show under the feature text, faint, as "What the rules engine does", never as
  card text. A mismatch check compares them with the text where it can ("increases to 3" vs `add 1`).

### 3.4 Storage chosen invisibly

| Author says | Editor writes | Why |
|---|---|---|
| A 1st-level feature | `tutoriallevel-N` (N from a small "arrives in encounter [1]" token, default 1); an opened `level-1` feature stays in `level-1` and shows "arrives after the slow start" | Book has one "1st-Level Features"; slow start is a DMHub detail. **Needs a decision** (Q1) |
| "You have the following ability" | One `CharacterFeature` + one `activated` modifier, feature name = ability name, description left empty | 601 records already look like this |
| "Choose one of" abilities | `CharacterFeatureChoice` with one single-ability feature per option | Same as 130 existing choices |
| Characteristic Increase | `CharacterFeatureList`: attribute feature(s) + choice of the others. "Increases to N" saves `max N`; "increases by 1, to a maximum of N" saves `add 1` + `cap N`; "is N" saves `set` | One sentence, one storage; opened variants keep theirs |
| Improves an earlier feature at level L | A feature at level L with `abilityimprovement` / `modifyability` (abilities) or a Level-keyed table on the original value (numbers). Opened `Level >= N` formulas show as "From level N" lines and are kept | Book shows the improvement at the new level |
| A heroic resource gain | One checklist entry (`name`, `details`, `mode`, `quantity`) + one trigger with a Replenish step whose `checklistid` is that entry's guid | Two records, one idea; linking by hand is error-prone |
| Starting Stamina A, +B per level | `hitpointsCalculation: "A + (Level - 1)*B"` (all 11 classes use this shape) | Book prints two numbers |
| Feature with rules and a triggered ability (Night Watch) | One feature, modifiers in order, trigger via the trigger editor (no `triggerdisplay`, brief 4j) | Book shows one feature |

### 3.5 Opening existing content safely

Same rule as abilities: anything the author did not change saves back as it was.
- Each block remembers the records it opened from and a fingerprint; unchanged blocks write their
  originals. A changed feature writes over its record, so `guid`, `domains`, `sourceReference`,
  `imported`, `importOverride`, `implementation`, `tags`, `canHavePrerequisites` survive.
- Empty level keys (`primary`, `multiclass`, `level-11..20`) are kept, never created or removed.
- **Risk to verify first:** today's editor calls `class:ForceDomains()` on every change. The test must
  show that domain recomputation is a no-op on unchanged content, or the simplified editor must only
  run it on features it changed.
- Modifiers inside a feature follow Section 4.5; abilities follow the ability editor's rules.

**Round-trip test** (a `poll/`-style script over `objectTables/classes` and `subclasses`):

| Check | Target |
|---|---|
| Opens without error | 70 / 70 |
| Untouched save identical | 70 / 70 |
| Rename one feature changes only its name | every feature (1,337) |
| Add a feature at level L touches only that level's `features` list | every level |
| Change one characteristic value touches only that modifier's `value` | 22+ increases |
| Opens entirely as blocks (no Advanced) | report |
| Book check: generated Advancement table vs book table; feature text vs book paragraph by `sourceReference` page | report per class |

### 3.6 Connection to the ability and trigger editors

- An ability feature shows its card collapsed in place; clicking opens the simplified ability editor
  for that `activatedAbility`, with the class passed in (resource word, keyword list, category names
  such as "Heroic Deceit" from `abilityCategoryNames`). Back returns to the class page at the same feature.
- Triggered features open the trigger editor; its generated card replaces `triggerdisplay` (124 in classes).
- Rule modifiers are the modifier editor's sentences, inline in the feature.
- **Paste:** a pasted class page goes through `DrawSteelRulesImporter.lua` (already parses "Classes"
  and "Kits" sections and stamps `imported`); a pasted feature with "You have the following ability."
  hands the card text to the ability paste reader. Unread sentences become "To build" blocks with
  "Save as pattern" (into `importerstandardfeatures`, which the rules importer already reads).

---

## 4. The Modifier editor

### 4.1 What authors struggle with today

Each modifier is a form built by its `TypeInfo.createEditor` (`DMHub Game Rules/CharacterModifier.lua`,
4,589 lines; power rolls in `MCDModifyPowerRolls.lua`, 4,400 lines). A newer search-first picker
exists (`Draw Steel Ability Editor/AbilityEditorModifierPicker.lua`) but only for choosing the type.

1. **Modify Attribute is five different ideas behind one dropdown** (1,854 uses): movement 276
   (speed, fly, climb, swim, burrow, disengage), characteristics 222, stability 104, Stamina 64, size
   63, and 189 custom attributes (963 uses; 667 of 1,060 custom uses are a flag set to 1, e.g.
   *Ignore Difficult Terrain* 65, *Immunity from Opportunity Attack* 46, *Freely Move Through Enemies*
   40, *Cannot Be Force Moved* 33). Operation is add / set / max / min with labels "Increase to" and
   "Decrease to" that read backwards to most people. **A new modifier defaults to `armorClass`**
   (`TypeInfo.attribute.init`), a 5e stat; three records still point at it (*Solo Turns*, *Hand of
   the Gods - Count as Ally*, *Shield? Shield!*).
2. **Modify Power Rolls is the largest modifier form** (about 30 labelled fields: Apply To,
   Characteristic, Resource Cost, Roll Requirement, Activation, Roll Mod, Modify Potency, Modify
   Resistance, Retarget Range/Distance/Filter/Effect, Damage, Damage Type, Damage Multiplier, Surges,
   Adjustments, Replace Movement, Add to Table, Replace in Table...). It has 27 `modtype`s (none 607,
   edge 292, bane 182, double edge 115, ...) and 8 roll types (ability 843, enemy ability rolls vs
   us 252, tests 200, ...).
3. **Three overlapping conditions on power modifiers:** `filterCondition` (does the modifier exist
   at all, 123), `displayCondition` (is it offered on this roll, 361) and `activationCondition` (is
   its box ticked by default: `True` 528, `False` 317, `1` 124, formulas ~350), plus
   `activationAfterRoll`. The "Activation" dropdown (Never / Always / Condition / Conditional After
   Power Roll) means "ticked by default", not "applies"; the label does not say so.
4. **Abilities are matched by name.** 114 `modifyability.filterAbility` formulas test a name or name-like field: `Ability.Free Strike` 62,
   `Ability.name is Judgment` 11, `Ability.name = "Melee Free Strike"` 6... A rename breaks these
   silently, like the `triggerdisplay` name match (brief 4j).
5. **GoblinScript everywhere.** 720 non-empty `filterCondition`s. The common shapes are intent
   blocks waiting to happen: `Level >= N` (102), `Self.Rampaging and Summoner.Level >= 10` (53),
   `AdjacentAlliesWithFeature("Shield? Shield!")` (45), `Monster Mode = 1` (22),
   `Heroic Resources This Turn >= N` (Growing Ferocity, 62), `Victories >= 5`, `Winded`.
6. **No readable summary.** Only 7 types have `autoDescribe`, and the attribute one reads "1 is
   added to your Speed" rather than the book's "Your speed increases by 1".
7. **The description field is player-facing in places authors don't expect.** For power modifiers
   `name` + `description` is the roll dialog's option tooltip (`MCDModifyPowerRolls.lua:1038`), yet
   most class modifiers just copy the whole feature text there (Section 3.1).
8. **The picker's "Common" band is not common:** it lists `proficiency`, `bestowcondition` and
   `abilityimprovement` (12 uses) but not `resistance` (383) or `modifyability` (309).

### 4.2 The blocks

Each modifier reads as one book-style sentence with underlined values. "Only if" wraps any of them
and compiles to the record's condition field, using the ability editor's test picker.

| Group (shelf order) | Sentence | Behaviour, fields | Uses |
|---|---|---|---|
| **Abilities** | You have the following ability [card] | `activated` -> ability editor | 1,052 |
| | When [event], [steps] | `trigger` / `powertabletrigger` -> trigger editor | 1,727 |
| | Your [ability or "free strikes"] gain(s) [+2 distance / extra target / fire damage / keyword] | `modifyability` (`range` 38, `damagetype` 28, `numtargets` 13, `cost` 6, `modkeywords` 6) | 309 |
| | You can't use [abilities matching ...] | `suppressabilities` | 57 |
| **Stats** | Your [speed / stability / size / Stamina] [increases by / is / increases to / can't exceed] [N] | `attribute` (add / set / max / min) | ~510 |
| | Your [Agility] score increases to [3] (... to a maximum of [N]) | `attribute` + `cap` | 222 |
| | You [ignore difficult terrain / can't be force moved / ...] | `attribute` flag = 1 | 667 |
| | You can [fly / climb / swim] [at your speed] | `attribute` movement | (in stats) |
| **Rolls** | You have [an edge / a double edge / a bane] on [tests using Hide, Sneak / ability rolls / Might tests] | `power`: `modtype`, `rollType`, `skills`, `keywords` | ~620 |
| | Abilities used against you have [a bane] | `power`, `rollType: enemy_ability_power_roll` | 252 |
| | Your [weapon] abilities deal [+2] extra damage | `power`: `damageModifier` (+ type, multiplier) | 208 |
| | [Increase / reduce] the potency by [1]; [tier 3 / not tier 1] outcome; costs [1 fewer] insight | `power`: `potencymod`, tier modtypes, cost | ~250 |
| **Defences** | You have [fire] immunity [5] / weakness [5] | `resistance` entries | 383 |
| | You can't be [frightened] | `conditionimmunity` | 65 |
| **Areas** | Creatures within [N] [have ...] | `aura` (reuses Create Aura block, brief) | 202 |
| **Resources** | You gain [N] [Recoveries / resource] | `resource` | 65 |
| | You have the [Hide] skill / speak [Caelian] | `proficiency` | 64 |
| **Conditions** | You are [slowed] | `bestowcondition` | 63 |
| **Reminders** | Reminder: [text] | `movementtext` | 89 |
| **Advanced** | Name + record summary + Settings (existing form) | 29 other types | 241 |

**Intent tests** for "Only if" (from the 720 formulas): *from level N*, *you have N+ [Ferocity]
this turn* (also the `growingresources` table, 11), *while winded*, *while an adjacent ally has
[feature]*, *in monster mode [2]*, *you have N+ Victories*, *you have your companion*, *the
summoner is level N+ and rampaging*. Everything else stays a raw formula block.

**Rolls get one "applies" sentence** instead of three conditions:

> [Always applies] / [You choose when you roll] / [Applies when ...] / [Choose after the roll],
> [offered only when ...]

Storage: Always -> `activationCondition: true`; You choose -> `false`; Applies when -> formula;
after the roll -> `activationAfterRoll`; "offered only when" -> `displayCondition`; an outer Only if
-> `filterCondition`. Opened records with several set show each as its own phrase.

### 4.3 Book first

The book never prints a modifier on its own; it prints the **owner's** text (a feature, kit bonus,
ancestry trait, condition, title, item). So:
- The card is the owner's saved text. The modifier sentence is the automation summary underneath,
  in book phrasing ("Your speed increases by 1", "You have a double edge on tests made to search
  for hidden creatures"), and is the generated text only when the owner has none.
- Where text is player-facing, the editor shows it as such: a power modifier's sentence previews
  the **roll dialog option** (name + description). New modifiers leave `description` empty instead
  of copying the feature text; the roll dialog falls back to the generated sentence (needs a small
  renderer change, Section 6).
- `autoDescribe` for the top behaviours is rewritten to the sentence table above, so the sheet,
  builder and `GetDescription` fallback all speak the same words.

### 4.4 Storage chosen invisibly

| Author says | Editor writes |
|---|---|
| "increases by N" / "is N" / "increases to N" / "can't exceed N" | `operation` add / set / max / min |
| "increases by 1, to a maximum of N" | add + `cap` |
| a flag ("you ignore difficult terrain") | custom attribute, `value: 1` |
| "When ..." with only ordinary steps | `trigger` |
| "When ..." with a Change-the-roll step | `powertabletrigger` (brief 4h) |
| A roll change with no triggering event | `power` |
| "Your Judgment gains ..." | `modifyability` with an ability picker; writes today's name formula until abilities can be matched by id (Section 6), and flags the dependency |
| Applies-when phrases | the four condition fields as in 4.2 |

### 4.5 Opening existing content safely

Every modifier keeps its record and fingerprint; unchanged sentences write the original. A changed
sentence writes over the original record, so the ~40 fields of a power modifier that no sentence
shows (`customTrigger`, `adjustments`, `damageTypeMappings`, `addText`, `ticksWith`...) survive.
Fields the sentence does not model are listed under it ("kept as they are"), as the ability editor does.

**Round-trip test:** all 8,023 modifiers in `objectTables` and `monsters`, by behaviour.

| Check | Target |
|---|---|
| Opens without error / untouched save identical | 8,023 / 8,023 |
| Edit one value (attribute value, edge to bane, immunity 5 to 10) changes only that field | per behaviour, 50 samples each |
| Opens as a sentence (not Advanced) | report; projected 96% by count |
| Conditions open as intent tests (not raw) | report against the 720 `filterCondition`s |
| Sentence agrees with owner text (mismatch list) | report, for content review |

### 4.6 Connection to the ability editor

- The ability editor's "While this ability resolves" block and "Apply an effect" settings currently
  fall back to the old modifier form; they use these sentences instead.
- A modifier list inside an ongoing effect, kit, ancestry or title uses the same sentences, so one
  vocabulary serves 1,504 ongoing-effect modifiers as well as classes.
- `activated` and the trigger types open the existing simplified editors; the trigger's card
  replaces `triggerdisplay` (354), per brief 4j.

---

## 5. Content findings to review (from this research)

| Finding | Where | Count |
|---|---|---|
| Characteristic Increase implemented five ways (add, add+cap, max, set, min) | Elementalist, Fury, Tactician... | 22+ |
| Elementalist characteristic `min 5` next to `add 1, cap 5` (min is a no-op below 5) | `classes/elementalist.yaml` | 4 |
| Modifiers copying their feature's full text into `description` | class records | 1,040 of 1,765 |
| Rule stated in a text-only feature but implemented elsewhere (Surge of Insight) | Shadow | 1 known; script can list more |
| Abilities matched by name in `modifyability` filters | all content | 114 |
| 5e `armorClass` attribute target | 3 modifiers | 3 |
| Level-1 features split between `tutoriallevel-1` and `level-1` | 8 records | 8 |
| Hidden duplicate domain records in `classes/` beside the live ones in `subclasses/` | domains | 14 |

---

## 6. Phased plan

| Phase | What | Gate |
|---|---|---|
| **1. Corpus scripts** (no UI) | Extend `ui-mockup/ability-blocks-corpus/` with `modifiers.js` and `classes.js`: open every record as blocks, save, diff; produce the counts and mismatch lists above | 8,023/8,023 and 70/70 untouched-identical; report sentence coverage |
| **2. Modifier sentences in the prototype** | The 12 sentences of 4.2 plus "applies" and intent tests, as a modifier list mode of the existing HTML page; Advanced blocks for the rest | Build the modifiers of 20 random features from their text; output equals content |
| **3. Class page in the prototype** | Shadow end to end: Basics, Insight, levels 1-10, College of Black Ash, generated Advancement table, links into the ability/trigger editor | Generated table matches the book's for all 11 classes; untouched save identical |
| **4. Poll** | 40 random features (all classes, all levels) and 40 random modifiers (monsters, effects, kits): open, save, edit, book-check, as polls 4m/4p | Untouched 100%; list of gaps ranked by count |
| **5. Lua** | `ModifierModel` and `ClassModel` beside the planned `TriggerModel`; sentence descriptors registered next to each `TypeInfo` (optional field, opaque fallback) | Same corpus scripts pass in Lua |
| **6. Engine and content (optional, each its own decision)** | Match abilities by guid in `modifyability`; roll-dialog fallback to the generated sentence; `triggerdisplay` migration (brief 4j); `ForceDomains` no-op check; content pass for Section 5 | Per item |

---

## 7. Risks

- **`ForceDomains` and `domains` churn.** If recomputation rewrites `domains` on every save, the
  identical-save rule fails for all 1,337 features. Must be measured in phase 1.
- **Two-record writes** (resource checklist + trigger; Characteristic Increase list + choice) can
  leave half a pair if a save fails. Write them in one `SetAndUploadTableItem` of the class.
- **Rules importer overwrite.** `imported` features are replaced on re-import unless
  `importOverride` is set. Editing an imported feature in the simple editor should set it (as
  "Override Import" does today) and say so.
- **Text-first editing can hide wrong automation.** Book wording wins on the card, so a mismatch
  between text and modifiers is invisible to players; the mismatch list must be prominent.
- **Scope creep into kits, ancestries and titles.** The modifier sentences make them cheap later,
  but this proposal only covers classes and the shared modifier list.

## 8. Open questions for the designer

1. *(Decided, see 9.1.)* **Level 1 placement:** should authors see the slow start at all? Options: (a) one "1st-Level
   Features" section with an "arrives in encounter N" token (recommended); (b) four Encounter
   sections as today; (c) always save to `tutoriallevel-1`.
2. **Improvements:** always a new feature at the later level (book first, recommended), or allow the
   "From level N" line inside the original feature as an authoring shortcut?
3. **Modifier descriptions:** stop copying feature text into new modifiers (recommended), and offer a
   one-click cleanup for the 1,040 copies, or leave content alone?
4. *(Decided, see 9.2.)* **Heroic resource:** is the checklist meant to be the source of truth (then triggers are
   generated from it), or are the triggers (then the checklist is generated)? The editor can write
   both either way, but one should win when they disagree.
5. **Hidden 5e fields** (`primary`, `multiclass`, Hit Die, spellcasting): hide entirely in the simple
   editor (recommended), or list them under Advanced?
6. **Subclass editing:** a subclass as its own page (as stored), or shown inside its class page in
   the book's table form with a link to edit it?
7. *(Decided, see 9.3.)* **Name matching:** accept an engine change so `modifyability` and similar filters match abilities
   by guid, or keep name formulas and warn on rename?

## 9. Decisions (2026-11-21)

**1. Level 1 and the slow start rules: a class toggle.** "Uses the slow start rules (Encounters 1-4)".
- On: the class page shows Encounter 1, 2, 3 and 4 sections, then "1st level, after the slow start".
  Saved as today: `tutoriallevel-1`..`tutoriallevel-4`, and `level-1` for the last section. The engine
  (`Class.lua`, levels before 1) gives a character in encounter N only the tutorial levels up to N, and
  `level-1` only once the slow start is over, so that section is real: Censor and Conduit keep their
  1st-Level Domain Feature there, Summoner its Circle choice, Troubadour Scene Partner.
- Off: one "1st level" section, saved to `level-1`; nothing in the tutorial levels.
- All 11 core classes are on (each has 9-16 features in the tutorial levels today). New classes default
  to off. Turning it off on a class that has encounter features asks where they go (all into 1st level).

**2. Heroic resource: the triggers win; the checklist is visual.** The resource sentence ("You gain [2]
[wrath] at the start of each of your turns") is the trigger, and the checklist entry players see is
generated from the same sentence, so the two can't disagree. They stay two records underneath, linked
by `checklistid` as today; the checklist wording can be overridden for the sheet, book first. Opening
existing content where they disagree (different quantity or wording) shows both and lets the author keep
one; the poll should count how often that happens.

**3. Matching abilities by id, as the author sees it.** The sentence reads "Abilities named [Free Strike]"
and clicking the name opens a searchable list of the abilities this class (or creature) has, by name,
grouped by where they come from. The author only ever picks a name; the editor saves the ability's
`guid`, so renaming the ability later doesn't break the filter, and the sentence always shows the
current name. Broad filters stay as they are ("abilities with the Strike keyword", "your signature
ability"). Engine work: `modifyability` and similar filters need to accept an id list alongside the
formula; until then the editor can write the name formula and warn on rename. Opening content: a name
formula that matches exactly one ability by name opens as that ability (and can be converted to the id
on save); anything more complex stays a formula.

**4. Class editor layout: levels as lanes, ready-made features (2026-11-22).** Approved from the design
visuals (`ui-mockup/modifier-blocks-design.html`, panel 6). Levels (and Encounters 1-4 when the slow start
toggle is on) are lanes; a feature is a container holding its name, its book text and modifier sentences;
features are dragged onto a level from a shelf. The shelf offers ready-made features for what core classes
repeat (Skills 69, Perk 54, Choose a heroic ability ~45, Characteristic Increase 33, Subclass choice 12,
Recoveries 11, Signature ability 9, Kit 7, Languages, Heroic resource gain) and an empty feature built from
sentences. Ready-made features are saved templates that a table or organisation can extend; dragging one in
copies it, so editing the copy never changes the template, and every sentence inside stays editable. The
preview shows the level as the book prints it ("2nd-Level Features", each feature's name, text and ability
cards). Next step: a working board in the prototype on real Shadow data, with the class open-and-save test.


## 10. Working prototype: Class Builder (2026-11-22)

Asked for: a shareable HTML prototype that is a class builder, to test making modifiers and abilities.
At the designer's request it starts from a **blank class** (no core class data is loaded).
Source: `ui-mockup/class-builder/` (`index.html`, `app.js`, `tables.js` built by
`ui-mockup/class-builder-data/build_data.py` from the compendium's skills, languages, conditions,
damage types, custom attributes and resources).

- **Board:** Basics (characteristics and arrays, Stamina), the heroic resource
  (name, epic resource, and "how you gain it" sentences), then level lanes. The slow start toggle adds
  Encounters 1-4 and "1st level, after the slow start"; turning it on moves 1st-level features into
  Encounter 1, and turning it off asks before moving encounter features into 1st level.
- **Ready-made features** (drag onto a level or click): Perk, Skills, Characteristic Increase, Choose a
  heroic ability (with its cost), Signature ability, Subclass choice, Kit, Recoveries, Languages, Feature
  with an ability, Feature with a triggered ability, Empty feature. **They are pre-filled blocks**, in the
  same design language as every other block (designer feedback: a separate settings form for perks and
  skills didn't match the editors). **Choices** is a block group: choose a perk, Skills (one block for
  skills the hero has and skills the player chooses; it saves a proficiency modifier, a skill choice, or
  both in a feature list, as needed), raise a
  characteristic, choose an ability (cards inside the block), choose your subclass (reads "Choose your
  [feature name]", so what subclasses are called is just the feature's name: College, Circle, Domain). The feature's record
  type is decided from its blocks, never picked: modifiers only -> `CharacterFeature`; one choice alone ->
  that choice (`CharacterFeatChoice`, `CharacterSkillChoice`, `CharacterFeatureChoice`,
  `CharacterSubclassChoice`); a mix -> `CharacterFeatureList` with a hidden feature holding the modifiers,
  then each choice (how core classes store Characteristic Increase). Choices can't sit inside "Only if".
  Basics and the resource name read as header blocks, and each way to gain the resource is a block.
- **Sentences** (Section 4.2): change a stat, movement type, "you have" a custom attribute, edge or bane on
  tests/ability rolls (with the "always applies / you choose" phrase), rolls against you, extra damage,
  immunity or weakness, can't be (condition), skill, language, Recoveries or a resource, kit, gain an
  ability, gain a triggered ability, change an ability (by name), reminder, and "Only if" (Victories,
  level, winded, Strained, or a formula) which writes `filterCondition` on what's inside. "Show saved
  fields" puts each sentence's record under it.
- **Abilities and triggers** open the simple ability editor in a pop-up (its new `?embed=1` mode: the
  builder sends the record, Done sends the saved record back). A heroic choice's new ability starts with
  the choice's cost and the class's resource name.
- **Resource gains** write both the checklist line and the trigger that grants it, linked by
  `checklistid` (decision 2: the trigger wins); the triggers sit in a hidden feature in the first level.
- **Saved data** column: the open feature's record and the whole class record, with Copy. (A book-page
  preview was tried and removed at the designer's request: the class builder doesn't need one.) A feature
  without its own text reads as its blocks.
- **Formula amounts (fx):** resource gains, stat values, extra damage, immunity and resource amounts take
  a number or a formula (quick picks: Victories, a die, level, a characteristic) and can change with level
  ("1d3, 1d3 + 1 from 7th level"). The checklist line saves the level steps as a `GoblinScriptTable` (as
  Shadow's content does); the trigger and modifiers save `(1d3 + 1) when Level >= 7 else (1d3)`.
- **Sharing:** Export gives the builder's own class as text to copy; Import opens it (pasted or a .json
  file). Work in progress is kept in the viewer's browser.

Checks to make before relying on these records: weakness is saved as negative damage reduction; perk
group tags are written as "<group> perk"; movement attributes other than fly and climb (`swim`, `burrow`)
are assumed ids.

## 11. Critique round 1: Class Builder, Hodent lens (2026-11-22)

An independent reviewer worked through five tasks in the prototype, at desktop and phone width and with
the keyboard only. Its findings are merged here with the designer's own pass, which looked at
consistency with the ability editor. **These are proposals, not decisions.**

| Pillar | Rating |
|---|---|
| Signs and feedback | Mixed: blocks and saved data update live; moves, deletes, undo and the slow start move are silent |
| Clarity | Mixed: blocks read like the book; "fx", `when Level >= 7 else`, "N ... 3", unexplained counts leak through |
| Form follows function | Mixed: a level per lane fits; a permanent JSON column doesn't fit non-programmer authors |
| Consistency | Mixed: blocks and colours match the editor; there are two shelves with a "Skills" in each, and the slow start toggle confirms only one way |
| Minimum workload | Mixed: ready-made features are fast; defaults cost unticks; only one feature can be open at a time |
| Error prevention and recovery | Weak: undo is in memory only, Import replaces your class, Delete is silent, Cancel leaves junk, typed text goes stale |
| Flexibility and accessibility | Weak: every edit loses keyboard focus; hover text is a browser tooltip; the editor pop-up breaks at phone width |
| Engage-ability | Mixed: watching cards appear in a choice is rewarding; the JSON wall and design-brief notes break the flow |

Ranked problems:
1. **There is no class-level status.** The ability editor's best feature, "Ready to save / N things to
   finish" with one-click fixes, has no equivalent here (designer). Nothing flags:
   - an ability choice with no abilities;
   - an unfinished ability inside a feature;
   - an empty "Only if";
   - an unnamed feature;
   - text that disagrees with its blocks.
2. **Every edit loses keyboard focus.** The whole board re-renders and focus returns to the top of the
   page. That costs about 22 Tabs to reach level 1 again, and arrow keys don't work in menus.
3. **Book text goes stale silently.** Typed text wins, and then changing a block (immunity 5 to 10)
   leaves "fire immunity 5" in the text with no flag. The ability editor flags reworded lines when the
   rules change.
4. **Recovery is fragile:**
   - undo is lost on reload, and there's no redo;
   - Import replaces the stored class;
   - Delete has no notice.
5. **Cancel leaves junk:**
   - a "New ability" placeholder card in a choice;
   - an empty Ability feature on the level;
   - Escape doesn't close the editor pop-up.
6. **Slow start on moves features silently**, and the encounter lanes aren't explained. Turning it off
   asks first; turning it on doesn't.
7. **The JSON column dominates the screen.** A quarter of the width is raw JSON for authors who aren't
   programmers (designer). The ability editor shows the result (the card) and keeps JSON under a
   disclosure. The feature footer's "Saved data" button is left over from the book page and does nothing
   now.
8. **There are two catalogues on the shelf:**
   - ready-made "Skills 69" and block "Skills 118" share a name;
   - the counts are unexplained;
   - every block stays greyed until a feature is open;
   - chips hide contents ("FEATURE Recoveries", not 10);
   - chip labels ("FEATURE" for Kit) don't use the shelf's names.
9. **Programmer details leak through:**
   - "Only if you have N or more Victories 3";
   - the fx menu's "Saves as (1d3 + 1) when Level >= 7 else (1d3)";
   - the "design brief" note in the ability-name menu;
   - arrays typed as `[2, -1, -1] [1, 1, -1]`;
   - "Copy class JSON" and Export are two JSONs, and nothing says which one to share;
   - JetBrains Mono ligatures turn `>=` into a glyph in the saved data.
10. **Defaults and menus add work:**
    - Skills starts with all five groups ticked;
    - the picker covers its own sentence;
    - Enter closes the fx menu;
    - level steps default to level 4 with a copy of the value.
11. **Phone width:**
    - the editor pop-up keeps two columns (about 50px for "What is it");
    - the shelf is about 750px below the board;
    - Export's text box is cut off;
    - Import wraps onto three lines.

Keep:
- blocks that read like the book, with text generated from them;
- the editor's colours, drag ghost and lane highlight;
- "Move to..." as the non-drag path;
- ready-made features as editable pre-filled blocks;
- the fx quick picks and level steps (with the wording fixed);
- cards inside choices;
- in-page confirmations;
- linked checklist line and trigger for each way to gain the resource;
- "Only if" (Iron Skin took about 8 clicks).

More elegant alternatives considered:
- **A. A status panel in place of the JSON column.**
  - The column becomes the class's status: things to finish, each with a jump-to and a fix, and text
    that disagrees with its blocks (number checks).
  - The JSON goes under a disclosure.
  - Fixes 1, 3 and 7.
  - Failure: number matching flags prose like "3 or more".
  - (The reviewer proposed a book page here; the designer removed the book page earlier, so this
    keeps the column without it.)
- **B. Keyed re-rendering and durable history.**
  - Controls keep their focus across edits.
  - Undo and redo are saved with the draft.
  - Import opens as a new class beside the current one.
  - Fixes 2 and 4.
  - Failure: storage limits with large abilities; a class list adds housekeeping.
- **C. One shelf.**
  - Ready-made features are "recipes" in the same list as the blocks.
  - A block dropped on a level makes a feature named after it.
  - Fixes 8.
  - Failure: many thin one-block features.
- **D. A transactional editor and an explained slow start.**
  - Ability options are created only on Done, and Escape counts as Cancel.
  - The editor opens full-screen on phones.
  - Turning on slow start shows "4 features moved to Encounter 1 · Undo", plus a one-time explanation.
  - Fixes 5, 6 and 11.
  - Failure: full-screen loses the class context.

**Done (2026-11-22): A, the quick fixes, and B.**
- **A. A status column.** "Ready to save / N things to finish / worth checking", each item with Show and
  a fix where one is obvious. It covers:
  - features that do nothing, unnamed features, and an empty Only if;
  - abilities not built yet, or with things left to finish (the problems the editor reported on Done);
  - an ability choice with no abilities, or fewer than players choose;
  - missing values, a Skills block that gives nothing, the resource name and amounts.

  Chips with something to finish get a red mark. **Typed text remembers the blocks' wording** it was
  written against. When the blocks change, the feature shows "Does it still match?" with "Use the blocks'
  wording" or "The text is still right" (no number matching, so no false alarms on prose). The saved
  data moved under a "Saved data (for developers)" disclosure.
- **B. Focus and history.**
  - Focus: controls carry stable keys and keep focus across edits. Text fields commit after focus moves,
    so Tab works. Arrow keys move through menus, and Escape returns focus to the word that opened them.
  - History: classes are kept in a list in the browser, each with undo and redo that survive a reload
    (Redo button, Ctrl+Shift+Z or Ctrl+Y).
  - Import opens the class as a new class beside yours, and the Open list has New and Delete.
- **Quick fixes:**
  - **Leftovers:** abilities are only added on Done, so Cancel and Escape leave nothing behind (Escape
    works inside the editor).
  - **Slow start:** turning it on or off says "N features moved … · Undo", and a hint explains the
    encounter lanes.
  - **Delete:** deleting a feature, block or resource gain shows a notice with Undo.
  - **Wording:**
    - "Only if you have at least [3] Victories" and "you are at least level [5]";
    - the fx menu reads in words, and shows the formula only with "Show saved fields";
    - no design-brief note in the ability-name menu;
    - arrays are shown as numbers, standard by default and following the starting characteristics,
      with your own arrays one per line;
    - Export is now Share, and its text says what to do with it.
  - **Defaults:** Skills starts with no groups ticked (meaning any skill); Enter keeps the fx menu
    open; a new level step starts empty.
  - **Shelf:**
    - the counts are explained on hover;
    - blocks are never greyed out (with nothing open, a block starts a new feature);
    - the Skills block is renamed "Have or choose skills";
    - chips use the shelf's names (Kit, Resource, Triggered ability).
  - **Phone:** the editor pop-up is full-screen, in one column.
  - **Other:** the share box and file button are styled, and saved data no longer shows ligatures.

## 12. One shelf, and authors' own ready-made features (2026-11-22)

Asked for: alternative C from the critique, plus ready-made features authors make and share.

- **One shelf.** Ready-made features and blocks are now one list, grouped by colour (Choices, Stats, Rolls,
  Defences, Abilities, Languages, Resources and kits, Reminders, Only if), each group ordered by use.
  - **Dropping an entry on a level** makes a feature named after it: "Choose a perk" makes "Perk",
    "Have or choose skills" makes "Skills", "Kit" makes "Kit".
  - **Dropping it into a feature** adds its blocks where the gold line shows.
  - **Clicking** adds the entry to the open feature, or starts a new feature if none is open.
  - The lane's "+ add a feature" menu lists the same entries.
- **Recipes** are entries that add several blocks, or one block with presets. They sit beside their
  blocks, marked "recipe":
  - Characteristic Increase (raised scores plus "raise another");
  - Signature ability;
  - Heroic ability choice.

  The plain "Choose an ability" block is offered only through those two recipes, and the separate
  Recoveries/Kit/Languages features are now just their blocks. That removes the duplicate entries.
- **Your ready-made features.**
  - **Saving:** "Save as ready-made" on any feature keeps a copy, with its abilities, in a "Your
    ready-made features" group at the top of the shelf. It's named on save, and dragging it in copies
    it with fresh ids.
  - **Managing:** each one has Share, Rename and Delete (Delete has Undo), and "Share all" copies the
    whole group as text.
  - **Importing:** Import accepts shared features as well as classes, and they join your shelf.
  - **Where they live:** in the prototype, in the browser. In DMHub they would be a compendium table, so
    a table or organisation can publish its own (see the Lua study).

## 13. Lua effort study (2026-11-22)

See `BLOCK_EDITORS_LUA_STUDY.md`, written by an independent study of the codex Lua; no Lua was changed.
- **Effort:** about 61-89 person-weeks for both prototypes, about 8-12 of them on rules and data changes.
  The first milestone, the simple ability editor on existing abilities, is about 25-35. No C# change is
  required.
- **Required changes:**
  - R1: one skill record (extend `CharacterSkillChoice` with `grantedSkills`, allow `numChoices = 0`).
    Old records keep working; the editor stops producing the two-part shape.
  - R2: the attribute `cap` field is never read (a live bug in content).
  - R3: perk tags match by exact text.
  - R4: change abilities by id.
- **Recommended changes:**
  - R5: card overrides on the ability;
  - R6: an aura "ends turn in the area" trigger;
  - R7: nested follow-up values.

The prototype was corrected for two findings I checked against the code:
- **"Raise a characteristic"** now saves +1 plus a separate `min` (cap) modifier, instead of `cap`
  (`CustomAttribute.lua` ApplyOperation has no cap).
- **Perk groups** use the tags perks actually carry ("exploration perks", "lore perks", "supernatural
  perks"; `Feat.lua` HasTag compares lowercased text exactly).

## 14. Start-of-turn heroic resource gain (2026-11-22)

**Asked for:** make gaining the heroic resource easier, keeping the start-of-turn gain in "Heroic
Resource Gain at Start" so complications and other features can change it.

**What content does** (data survey of the 11 core classes):
- **The attribute.** A modifier at 1st level adds to the custom attribute "Heroic Resource Gain at
  Start" (`4d6eb7b5...`). It adds 2 for flat classes (Censor, Elementalist, Null, Tactician, Summoner)
  and 3 for 1d3 classes (Beastheart, Fury, Shadow, Talent), where the attribute is the **die size**.
- **The trigger.** The `beginturn` trigger gains `Heroic Resource Gain at Start` (dice classes use a
  level table, "1d Heroic Resource Gain at Start", then "(1d ...) + 1" from 7th level). Its condition is
  `Heroic Resource Gain at Start > 0`.
- **The checklist line** shows `{Heroic Resource Gain at Start}`.
- **Level steps.** Flat classes add +1 at 7th and 10th level.
- **Switching it off.** Complications such as Self-Taught set the attribute to 0.
- **Conduit and Troubadour** gain an amount the trigger computes ("cast.Heroic Resources Gained").
- **Every gain.** A separate attribute, "Heroic Resource Gain Modification" (`61a3ee0a...`), is added to
  every heroic resource gain (`AbilityReplenish.lua:644`, `MCDMAbilityBehavior.lua:1946`).

**The builder:**
- **A start-of-turn block, first under "How you gain".** It reads "At the start of each of your turns,
  you gain [a set amount: 2 | a die roll: 1d3] wrath", with "+1 from 7th level" steps.
  - It writes the whole pattern above: the attribute modifier(s), the trigger with the > 0 condition,
    and the checklist line.
  - Flat steps are attribute modifiers with `Level >= N`; die steps are table rows.
  - The ⋯ menu offers "This class doesn't gain at the start of its turn".
- **Other gains** (combat starts, dealing damage, and so on) stay as event blocks.
- **"Change a stat"** offers "start-of-turn Wrath gain" and "every Wrath gain", named with the class's
  resource. A complication, title, item or later feature can then change them without anyone knowing
  the attribute names.
- **Older classes** move their start-of-turn gain into the block.

**Open question (content consistency).** For 1d3 classes the attribute is the die size, so "+1 to
start-of-turn gain" from a complication makes the roll 1d4. For flat classes it adds 1. Options:
- (a) Keep the meaning per class, and have the block say which it is.
- (b) Give dice classes a separate bonus: the attribute always means "added to the gain", and the die
  size becomes its own value.

(b) is consistent for modifiers but changes four classes' data.

**Decision (2026-11-22): keep the data as it is (option a).**
- **The rules:** dice classes improve with bonuses ("1d3 + 1", "+ 2"), not bigger dice, and the block
  already saves its level steps that way (table rows "(1d ...) + 1"), as content does.
- **Why the attribute stays:** it remains the die size for dice classes, because content uses it as the
  on/off switch (Self-Taught and Gloom Squad set it to 0; Summoner's Essence at Start sets it from
  stacks).
- **What the builder says:** for a dice class it names the stat "start-of-turn Wrath die size (1d3)",
  and the block notes that level bonuses add to the roll. To add to the amount, there's "every Wrath
  gain" (Heroic Resource Gain Modification).
- **Book text** reads "1d3 (1d3 + 1 from 7th level, 1d3 + 2 from 10th level)".

## 15. Growing tables (2026-11-22)

**Asked for:** growing resource tables, where several classes gain benefits from the most heroic resource
they've had at any point during their turn.

**What content does:**
- **Where they appear.** Eleven `growingresources` tables: Fury's Growing Ferocity per subclass and per
  stormwight kit, the Null's Psionic Mastery per tradition, and Beastheart's Rampage.
- **The table.** Each is a display-only table (`Draw Steel Modifiers/ModifierGrowingResources.lua`):
  rows of threshold, minimum level, short sheet text and tooltip.
- **The rules.** The rules for each row are separate modifiers (power, trigger, attribute,
  modifyability) whose conditions read `Heroic Resources This Turn`. That's the turn's high-water mark
  (`MCDMCreature.lua:1836`, `HeroicResourceHighWaterMarkForTurn`).
- **Replacement.** A row that replaces an earlier one ("2 surges instead of 1", "double edge") makes
  the earlier row's condition exclude it: `Heroic Resources This Turn >= 6 and (Heroic Resources This
  Turn < 10 or level < 7)`.
- **The problem for authors:** they write the table text and the conditions separately, and the two
  can disagree.

**The builder: a Growing table block** (one "Growing table" recipe on the shelf, with rows at 2, 4 and
6, then 8 from 4th level, 10 from 7th and 12 from 10th).
- **Rows.** Each row is "At [N] ferocity, from level [L]" and holds ordinary blocks (no choices or
  nested tables). A row can say "replaces the row at N"; the default is "adds to earlier rows".
- **Sheet text.** Each row's sheet text is written from its blocks, and can be overridden. The tooltip
  is the full wording.
- **What it saves:** the `growingresources` table, plus every row's modifiers with conditions written
  for it.
  - Unlocked: `Heroic Resources This Turn >= N` (and `Level >= L`).
  - Replaced: `and (Heroic Resources This Turn < N2 or Level < L2)` for each row that replaces it.

  A test rebuilding Berserker's table produced the same conditions as the content.
- **Only if** also offers "you've had at least [N] ferocity this turn", for one-off benefits outside a
  table.
- **Status.** An empty row is "worth checking" (only its sheet text would show).

## 16. Coverage of the core classes (2026-11-22)

A script (`ui-mockup/class-builder-data/coverage.py`, `coverage2.py`) surveyed the 11 core classes and
their subclasses. It listed every feature type, modifier behaviour and field, and what the class builder
can make.

**Covered:**
- **Features:** feature, choice, list, skill choice, perk choice, subclass choice, which is 1,809 of
  about 1,980 features.
- **Modifiers:** activated 613, attribute 397, trigger 269, power 212, trigger display 115, modify
  ability 68, power roll trigger 50, resistance 36, resource 34, proficiency 30, kit 8, growing table 6,
  condition immunity 5, reminder 3. That's about 1,850 of about 1,960 modifiers.

**Gaps, most used first:**

| Gap | Uses | Classes | What it is | Proposal |
|---|---|---|---|---|
| Effects defined inside a feature (`CharacterOngoingEffect`) | 51 | 9 of 11 | Effects that a feature's abilities or triggers apply ("Rampaging - Surges On Ally Damage") | "Effects" section in a feature: name, duration, blocks inside (the modifier sentences); the ability editor's "Apply an effect" can pick them |
| Usage limits on triggers (`resourceRefreshType`) | 60 | all 11 | Once per round / turn / encounter / respite / victory | A phrase on the trigger block: "[once per round]"; check the ability editor writes it |
| Power roll options with a cost (`resourceCostType: cost`) | 52 | 7 | "Spend 1 wrath: ..." edges, damage and tier changes on a roll | An "applies" choice: "you can spend [1] [wrath] when you roll"; also tier changes (`tier3`, `replaceroll`, `tierup`) as Rolls blocks |
| Auras (`aura`) | 28 | 5 | Blessings, Null Field-like areas around you | Reuse the ability editor's Create Aura block as a modifier sentence |
| Domain prerequisites (`CharacterPrerequisite` type domain) + Deity and Domains choice | 150 + 2 | Censor, Conduit | Domain features offered only if the deity grants that domain | "Choose your deity and domains" choice block, and "Only offered with the [Fate] domain" on a choice option |
| Companion (`modcompanion`, `CharacterCompanionChoice`) | 23 + 1 | Beastheart | Changes to the companion (characteristic increases apply to both) | "Your companion" as the target of stat/rolls blocks; a companion choice block |
| Summoner minions (`modsummoner`) | 7 | Summoner | Minion stat improvements by tier | A "Your minions" target, like the companion |
| Routines (`routine`) | 13 | Troubadour | Performance abilities with their own display | Routine ability card via the ability editor (aura-like "while this performance is active") |
| Ability improvements (`abilityimprovement`) | 10 | Null, Talent | Optional augments with a cost (Expanded Power) | "Your [Psionic] abilities can [increase their area by 1] for [N] [clarity]" |
| Modify a trigger (`modifytrigger`) | 7 | Summoner, Talent, Troubadour | Changes an existing triggered ability | Like "Change an ability", for triggers |
| Add to the resource checklist (`modifyresourcechecklist`) | 5 | Troubadour subclasses | A subclass adds a way to gain the resource | The "How you gain" blocks, offered inside subclass features |
| Suppress abilities, forced movement swaps, bestow condition, alternate appearance, journal explanation, power-table additional | 1-3 each | - | Rare | Advanced block (saved untouched) |
| Ability category names (`abilityCategoryNames`) | 4 classes | Conduit, Elementalist, Fury... | "Signature Prayer" / "Heroic Spells" | Basics row: "Your abilities are called [Prayers]" |
| Subclasses (`subclasses` table: `primaryClassId`, own levels and checklist) | 33 subclasses | all | Subclass features at levels 1-10 | The same builder in "subclass" mode: lanes, no basics, linked to the class |

## 17. Cross-class gaps 1-4 built (2026-11-22)

1. **Effects inside abilities.**
   - **Where they are:** the survey's 51 "effects defined in a feature" are actually the
     `momentaryEffect` of "While this ability resolves" steps (`ActivatedAbilityApplyAbilityDurationEffect`)
     inside abilities and triggers. That makes them an ability editor gap.
   - **The fix:** the ability editor's block now lists the effect's rules as lines, in read mode like
     every block: change a stat (43 of the 67 rules), edge or bane, and extra damage. Each has
     "+ rule" and ✕. Other rules (triggers 11, resistance, modify ability) show as "kept as it is" and
     save unchanged.
   - **Safety:** edits change the modifier in place, on a copy taken when the ability opens. The three
     save-back test samples are still identical (45/45, 60/60, 1,148/1,148), and an opened ability's
     effect saves byte-identical when untouched.
2. **Usage limits.**
   - **The phrase:** ability and trigger blocks have "Usable [1] time [per turn | per round | per
     encounter | per respite | until you earn a Victory]".
   - **Saved as:** the modifier's `resourceRefreshType` and `numCharges`. Respite is the engine's
     "long"; "victory" is Draw Steel's own refresh type (`Resource.lua` 475-545).
3. **Power roll options with a cost.**
   - **The cost choice:** the roll blocks' "applies" phrase has a third choice, "if you spend [1]
     [wrath | surges | epic resource] when you roll". It saves `resourceCostType` cost/surges/epic,
     `resourceCostAmount`, and `activationCondition` true, as content does
     (`CharacterModifier.lua:3719`).
   - **New Rolls blocks:** "Change the outcome" (tier 3, not tier 1, up or down a tier, not tier 3,
     tier 1; content's modtypes) and "Change potency" (`potencymod`).
4. **Auras.** An Aura block (its own group): "You have an aura of [3] squares. [You and each ally | Each
   ally | Each enemy | Each creature | Each other creature] in it:" with blocks inside. It saves the
   `aura` modifier with `radius` and an `Aura` holding the inner modifiers and `applyto`. Rebuilding
   Censor's Blessing of Iron gives content's shape.

Also fixed: wording from a block with its own sentence lost the "If ..." or "While within ..." lead-in
of the Only if or aura around it.

## 18. Shelf organised by what it does for the character (2026-11-22)

Asked for: no "Choices" group, no single-block groups, growing tables under resources, and a Common list at
the top. Groups now say what an entry gives the character; a choice sits with what it gives.

| Group | Entries |
|---|---|
| Common | Gain an ability, Gain a triggered ability, Change a stat, Edge or bane on rolls, Have or choose skills, Choose a perk, Characteristic Increase, Heroic ability choice, Empty feature (hand-picked; each also stays in its group) |
| Stats | You ignore / can't..., Change a stat, Raise a characteristic, Characteristic Increase (recipe), Movement type |
| Rolls | Edge or bane, Rolls against you, Extra damage, Change potency, Change the outcome |
| Defences | Immunity or weakness, Can't be (condition) |
| Abilities | Gain a triggered ability, Gain an ability, Change an ability, Heroic ability choice (recipe), Signature ability (recipe) |
| Skills, perks and languages | Have or choose skills, Choose a perk, You know a language |
| Class, kit and resources | Recoveries or a resource, Choose your subclass, Growing table (recipe), Kit |
| Only if, auras and reminders | Only if, Reminder, Aura |

Your ready-made features stay at the very top.

**Rename (2026-11-22): "Only if" is "Logic".**
- **The block's name** is now "Logic" on both shelves, in the ability editor and the class builder. Its
  sentence still reads "Only if [you have at least 3 Victories]".
- **Messages follow the new name:** "Wrap in Logic (Only if...)", "A Logic block in ... has nothing
  inside", "This Logic block needs a test".
- **The group** "Only if, auras and reminders" became **Logic**. **Aura** moved to Abilities, and
  **Reminder** to "Class, kit, resources and reminders".

## 19. Prose pass on the builder's help text (2026-11-22)

The help text was rewritten to say what the author can do, or what happens in play. It no longer
describes how the class is stored. Words like "record", "modifier", "trigger", "checklist line"
and "attribute" now appear only under **Show saved fields** and in the developer's saved-data panel.

- **The rule for writing help text:** one sentence on what the block does for the hero, plus,
  where it helps, one on how to use it. Never say how it is saved.
- **Examples:**

  | Before | After |
  |---|---|
  | "Each way writes the sheet's checklist line and the trigger that grants it, linked so they can't disagree." | "Each of these is listed on the hero's sheet, and the game adds the [resource] for them when it happens." |
  | "Text shown to the player as a reminder. Automates nothing." | "A note on the hero's sheet, for a rule the game can't apply for you. It doesn't change anything in play." |

- **Block descriptions:** the "Saves as ..." endings are gone from perk, skill and stat blocks.
  "Pairs with 'score increases to' blocks" and "triggered mode" are also gone.
- **Start-of-turn note removed:** the note under the start-of-turn gain is gone. The level steps
  already show the 1d3 + 1 and + 2 bonuses, and the stat picker lists the start-of-turn gain for
  other features to change. The note still appears under Show saved fields.
- **Shelf counts removed:** the shelf no longer shows how often the core classes use each block. That count still sets the order within a group.
- **Errors:** the import error no longer says "JSON" or "Export". The empty-status line ("the
  class saves as the records below") was removed, because the status already says "Ready to save".

## 20. Logic tests built like the ability editor's (2026-11-22)

The Logic block used to offer one of six fixed tests ("you have at least [5] Victories", "you are
winded"...). Because the default showed Victories, the block looked as if Victories was the only
test. The block now works like the ability editor's: **Only if [+ choose a test]**. Clicking the
test opens the same kind of picker, with a search box, test groups, and "Type a formula instead".

- **What a class test can check:** a class feature only knows about the hero who has it. So the
  ability editor's target, potency, "kind of creature" and triggering-event tests are left out,
  and every test is about **you**:

  | Group | Tests |
  |---|---|
  | Strained (Talent) | You are Strained / not Strained |
  | Check a condition | You are prone, slowed, grabbed... (every condition) |
  | Check health | You are winded; your Stamina is at most N; you are dying |
  | Check the moment | It is your turn; you are in combat |
  | Compare a number | Victories, level, any characteristic, Stamina, Recoveries left, your resource, the most resource this turn, the combat round, compared with at least / at most / is / is not |
  | Combine tests | All of these are true; any of these is true; not |

- **How it saves:** tests are stored as a small tree (`{ t: "cmp", a: "Victories", op: ">=", n: "5" }`).
  They compile to GoblinScript on the modifier's filter condition, e.g.
  `(Victories >= 3 and not Strained)`. The book text reads "If you have 3 or more Victories and you
  are not Strained, ...".
- **Status and old saves:** a Logic block with an empty test, or an empty slot inside a
  combination, is listed in the status column as "needs a test". Saved classes and ready-made
  features using the old six tests are converted when they load.

## 21. Resource gains that use a formula read as a sentence (2026-11-23)

When the amount of a resource gain is a formula, the gain now reads "When combat starts, you gain a
number of resolve equal to your Victories" instead of "you gain Victories resolve". A plain number
or dice still reads "you gain 2 resolve". The text shown on the hero's sheet uses the same wording.
The comma now also sits right against the event ("When combat starts,").

## 22. Roll options: Offered when and Ticked (2026-11-23)

A roll modifier answers three questions. The roll blocks (Edge or bane on rolls, Extra damage,
Change the outcome, Change potency) now ask each one in plain words, with the same "+ test"
chips as Logic:

| Question | Where | Saves as |
|---|---|---|
| Does it exist right now? (early exit) | A **Logic** block around the roll block. It can only test you. | `filterCondition` |
| Is it offered on this roll? | **Offered when [+ test]** under the block. Empty means every matching roll. | `displayCondition` |
| Does its box start ticked? | **Ticked** [automatically / automatically when [+ test] / by the player / if they spend N] | `activationCondition` |

- **Test pickers for roll options:** these offer more than Logic does.
  - **The ability:** deals damage, signature, heroic, main action, maneuver, force moves, has the
    [keyword] keyword, or is [a named ability]. Ability names come from a picker, so there are no
    exact names to type.
  - **The target:** winded, concealed, has cover, minion, or any condition.
  - **The roll:** the number of targets. This appears only under "Offered when", because the engine
    does not give "Ticked" the cast (an engine gap; see below).
  - **About you:** everything Logic offers.
- **No repeated tests:** when the option should be ticked whenever it is offered, "Ticked
  automatically" saves `1`. Content today often writes the same test into both fields (Rays
  Ignis, concealment). Here the test lives only in "Offered when".
- **Checks:** "Ticked automatically when" with no test is flagged in Status, and so is an
  unfinished "Offered when" test.
- **Engine findings (recorded only):**
  - `hintPowerRoll` builds activation symbols without `cast`, while `shouldShowInPowerRollDialog`
    includes it. So `Cast.Target Count` works when offered, but not when ticked.
  - The after-roll pair (`displayAfterRoll` / `activationAfterRoll`) is used 5 times. It is not
    in the blocks yet and stays in the old Modify Power Roll editor as the backup.

## 23. "Automatically selected", and tests ordered by use (2026-11-23)

- **Renamed:** the roll block's "Ticked" line is now **Automatically selected**, with the choices
  always, when [+ test], never (the player chooses), or always, and it costs N [resource].
- **Test order in both editors:** "Combine tests" stays first. The rest are ordered by how often
  the compendium's 5,201 condition and filter formulas use them:

  | Test | Uses |
  |---|---:|
  | The ability's keywords | 340 |
  | Level | 339 |
  | The ability's name | 282 |
  | Potency | 205 |
  | Characteristics | 193 |
  | Your conditions | 155 |
  | The target's conditions | 137 |
  | Deals damage | 125 |
  | Winded | 105 |
  | Concealed | 89 |
  | Stamina | 76 |
  | Resource this turn | 71 |
  | Victories | 51 |
  | Strained | 10 |

  "Kind of creature", mostly "enemy", has 473 uses and leads the ability editor's list after
  Combine and Compare.
- **Groups that only some boxes have** (the triggering event, the parent ability, remembered
  values) come right after Combine. "Remembered values" drops to the bottom while nothing is
  remembered yet.
