# Trigger Event Prose Worksheet

Companion to [TRIGGERED_ABILITY_EDITOR_DESIGN.md](TRIGGERED_ABILITY_EDITOR_DESIGN.md), [TRIGGER_SYMBOL_PROSE.md](TRIGGER_SYMBOL_PROSE.md), and [BEHAVIOUR_PROSE.md](BEHAVIOUR_PROSE.md). This is the launch-scope enumeration of trigger event phrases used to compose the **Trigger row** of the auto-derived preview card and the **"Triggers when" clause** of the Mechanical View's Trigger Summary.

**Why we need this:** the Trigger row of the card (and the Mechanical View's when-clause) reads as a single plain-English sentence combining three parts:
- **Subject phrase** (from `ability.subject` via the dynamic subject prose table: `"you"`, `"any enemy"`, `"you or any ally"`, etc. -- see [TRIGGER_SYMBOL_PROSE.md](TRIGGER_SYMBOL_PROSE.md) Subject section for the full lookup table)
- **Event phrase** (from `ability.trigger` id, via the templates on this worksheet)
- **Condition phrase** (from `ability.conditionFormula` via the prose engine, optional)

Composed as: `[event phrase][, if [condition phrase]]`. The event phrase is a clause that already positions the subject inside it -- not a bare verb tacked onto the subject.

Example composition (subject=`enemy`, trigger=`losehitpoints`, condition=`Damage >= 5 and Damage Type is "fire"`):
- Event template: `"when {subject} takes damage"`
- Subject role prose: `"any enemy"` (from subject=`enemy`)
- Condition prose: `"the damage is at least 5 and the damage type is fire"`
- Composed: *"When any enemy takes damage, if the damage is at least 5 and the damage type is fire."*

When `conditionFormula` is empty, the comma clause is omitted -- e.g. Stand Fast (subject=`self`, trigger=`beginturn`, no condition): *"At the start of your turn."*

**Voice:** `self` renders as second person (`you` / `your`) to match player-facing card voice -- see the Subject voice decision in [TRIGGER_SYMBOL_PROSE.md](TRIGGER_SYMBOL_PROSE.md). Every other subject id stays third person.

**Verb agreement markers.** English 2nd-person present uses the base verb form ("you take damage") while 3rd-person singular needs -s / -es ("any enemy takes damage", "any enemy finishes an ability"). Templates mark agreement-sensitive verbs with three placeholders:
- `{s}` -- regular -s suffix. Composer substitutes `""` when subject is exactly `"you"`, `"s"` otherwise. Example: `{subject} take{s} damage` -> `"you take damage"` / `"any enemy takes damage"`.
- `{es}` -- -es suffix for stems ending in -s/-sh/-ch/-x/-z. Composer substitutes `""` when subject is exactly `"you"`, `"es"` otherwise. Example: `{subject} finish{es} an ability` -> `"you finish an ability"` / `"any enemy finishes an ability"`.
- `{is}` -- irregular "is"/"are" verb. Composer substitutes `"are"` when subject is exactly `"you"`, `"is"` otherwise. Example: `{subject} {is} targeted by an ability` -> `"you are targeted by an ability"` / `"any enemy is targeted by an ability"`.

Compound subjects (`you or any ally`, `you or any hero`) follow the proximity rule and use 3rd-singular agreement -- `{s}` substitutes to `"s"` -- so `"you or any ally takes damage"`, `"you or any hero is targeted by an ability"`. Detection is literal-string: the composer only strips `{s}` and uses `"are"` when the subject prose equals `"you"` exactly.

---

## Your job

Review the proposed prose template for each trigger. Edit the text freely. Use the Status column to track progress: `OK`, `EDIT`, `DEFER`.

**Template rules:**
- Templates are full clauses, lowercase, starting with whatever reads best (`when`, `at the start of`, `just before`, `after`, etc.). The composer capitalises the first letter and optionally prepends/appends punctuation.
- Three placeholders available:
  - `{subject}` -- subject role form (e.g. `you`, `any enemy`, `you or any ally`). Used as the clause's noun-phrase subject.
  - `{subject-possessive}` -- subject possessive form (e.g. `your`, `that enemy's`, `that creature's`). Used when the event is positioned around a creature's belonging (`at the start of {subject-possessive} turn`).
  - `{s}` / `{is}` -- verb agreement markers. See the Voice section for substitution rules.
- Global events (round start, end of combat) omit the subject placeholder entirely.

**Out of scope:**
- `hit`, `miss`, `fumble` -- DS-hidden or deregistered (see design doc gotcha 5).
- `attacked` is **in scope** and active -- `dnd5e.lua` runs in DS and seven compendium entries actively use this trigger. Entry lives at the bottom under "5e-derived trigger" rather than in a themed band since it isn't DS-native.

**Codebase bugs to flag during implementation** (unchanged from TRIGGER_SYMBOL_PROSE.md):
- ~~`forcemove.hasattacker` declared as `creature`, should be `boolean`.~~ **FIXED 2026-04-28.**
- `AbilityRoutineCast` type id `rouitineControl` -- typo for `routineControl`. Data-migration, separate from this work.

---

## Common-band triggers

Priority-sorted for display. These are the most-used triggers per the design doc's picker modal spec.

### `losehitpoints` ("Take Damage")
- **Engine description:** Fires when the subject loses stamina from damage.
- **Template:** `when {subject} take{s} damage`
- **Example (subject=self, no cond):** *"When you take damage."*
- **Example (subject=self, cond=`Damage >= 5`):** *"When you take damage, if the damage is at least 5."*
- **Example (subject=enemy):** *"When any enemy takes damage."*
- **Status:** `OK`

### `dealdamage` ("Damage an Enemy")
- **Engine description:** Fires when the subject deals damage to an enemy.
- **Template:** `when {subject} deal{s} damage to an enemy`
- **Example (subject=self):** *"When you deal damage to an enemy."*
- **Status:** `OK`

### `rollpower` ("Roll Power")
- **Engine description:** Fires on any power roll. 2d10 results are exposed as symbols.
- **Template:** `when {subject} make{s} a power roll`
- **Example (subject=self, cond=`Natural Roll >= 18`):** *"When you make a power roll, if the natural roll is at least 18."*
- **Status:** `OK`

### `inflictcondition` ("Condition Applied")
- **Engine description:** Fires when a condition is inflicted on the subject.
- **Template:** `when a condition is applied to {subject}`
- **Example (subject=self, cond=`Condition is "Grabbed"`):** *"When a condition is applied to you, if the applied condition is Grabbed."*
- **Status:** `OK`

### `useability` ("Use an Ability")
- **Engine description:** Fires when the subject uses any ability.
- **Template:** `when {subject} use{s} an ability`
- **Example (subject=self, cond=`Ability.Keywords has "Strike"`):** *"When you use an ability, if the used ability's keywords include Strike."*
- **Status:** `OK`

### `beginturn` ("Start of Turn")
- **Engine description:** Fires at the start of the subject's turn.
- **Template:** `at the start of {subject-possessive} turn`
- **Example (subject=self):** *"At the start of your turn."*
- **Example (subject=enemy):** *"At the start of that enemy's turn."*
- **Status:** `OK` (note: this template uses `{subject-possessive}` which inserts the possessive form from the subject table -- `your` for self, `that enemy's` for enemy, `that creature's` for compounds)

---

## Combat band

### `attack` ("Attack an Enemy")
- **Engine description:** Fires when the subject attacks an enemy.
- **Template:** `when {subject} attack{s} an enemy`
- **Example (subject=self):** *"When you attack an enemy."*
- **Status:** `OK`

### `dying` ("Become Dying (Heroes Only)")
- **Engine description:** Fires when a hero drops to 0 stamina and becomes dying.
- **Template:** `when {subject} become{s} dying`
- **Example (subject=self):** *"When you become dying."*
- **Status:** `OK`

### `winded` ("Become Winded")
- **Engine description:** Fires when the subject's stamina drops to the winded threshold.
- **Template:** `when {subject} become{s} winded`
- **Example (subject=self):** *"When you become winded."*
- **Status:** `OK`

### `fallenon` ("Creature Lands On You")
- **Engine description:** Fires on the subject when another creature falls onto them.
- **Template:** `when a creature lands on {subject}`
- **Example (subject=self):** *"When a creature lands on you."*
- **Example (subject=enemy):** *"When a creature lands on any enemy."*
- **Status:** `OK` (now mirrors the trigger's picker label verbatim for subject=self, thanks to the "you" rewrite)

### `creaturedeath` ("Death")
- **Engine description:** Fires when the subject dies.
- **Template:** `when {subject} die{s}`
- **Example (subject=self):** *"When you die."*
- **Status:** `OK`

### `zerohitpoints` ("Drop to Zero Stamina")
- **Engine description:** Fires when the subject's stamina reaches 0. Distinct from `creaturedeath` -- hero-death flow may not fire `creaturedeath` immediately.
- **Template:** `when {subject} drop{s} to 0 stamina`
- **Example (subject=self):** *"When you drop to 0 stamina."*
- **Status:** `OK`

### `gaintempstamina` ("Gain Temporary Stamina")
- **Engine description:** Fires when the subject gains temporary stamina.
- **Template:** `when {subject} gain{s} temporary stamina`
- **Example (subject=self):** *"When you gain temporary stamina."*
- **Status:** `OK`

### `kill` ("Kill a Creature")
- **Engine description:** Fires when the subject kills another creature with damage or an effect.
- **Template:** `when {subject} kill{s} a creature`
- **Example (subject=self):** *"When you kill a creature."*
- **Example (subject=any):** *"When any creature kills a creature."* (still reads slightly awkwardly when subject is any; most usage is subject=self)
- **Status:** `OK`

### `saveagainstdamage` ("Made Reactive Roll Against damage")
- **Engine description:** Fires after a resistance / reactive power roll against incoming damage.
- **Template:** `when {subject} make{s} a reactive roll against damage`
- **Example (subject=self):** *"When you make a reactive roll against damage."*
- **Status:** `OK`

### `regainhitpoints` ("Regain Stamina")
- **Engine description:** Fires when the subject regains stamina (healing).
- **Template:** `when {subject} regain{s} stamina`
- **Example (subject=self):** *"When you regain stamina."*
- **Status:** `OK`

---

## Abilities & Power Rolls band

### `finishability` ("Finish Using an Ability")
- **Engine description:** Fires after the subject finishes resolving an ability.
- **Template:** `when {subject} finish{es} using an ability`
- **Example (subject=self):** *"When you finish using an ability."*
- **Example (subject=enemy):** *"When any enemy finishes using an ability."*
- **Status:** `OK`

### `targetwithability` ("Targeted by an Ability")
- **Engine description:** Fires on the subject when another creature targets them with an ability.
- **Template:** `when {subject} {is} targeted by an ability`
- **Example (subject=self):** *"When you are targeted by an ability."*
- **Example (subject=enemy):** *"When any enemy is targeted by an ability."*
- **Status:** `OK`

### `castsignature` ("Use Signature Attack or Area")
- **Engine description:** Fires when the subject uses a signature ability with the Strike or Area keyword.
- **Template:** `when {subject} use{s} a signature ability or area ability`
- **Example (subject=self):** *"When you use a signature ability or area ability."*
- **Status:** `OK`

---

## Movement band

### `leaveadjacent` ("Adjacent Creature Moves Away")
- **Engine description:** Fires on the subject when a creature adjacent to them moves away.
- **Template:** `when a creature adjacent to {subject} moves away`
- **Example (subject=self):** *"When a creature adjacent to you moves away."*
- **Status:** `OK`

### `move` ("Begin Movement")
- **Engine description:** Fires when the subject starts moving along a path.
- **Template:** `when {subject} begin{s} moving`
- **Example (subject=self):** *"When you begin moving."*
- **Status:** `OK`

### `wallbreak` ("Break Through a Wall")
- **Engine description:** Fires when the subject breaks through a wall.
- **Template:** `when {subject} break{s} through a wall`
- **Example (subject=self):** *"When you break through a wall."*
- **Status:** `OK`

### `collide` ("Collide with a Creature or Object")
- **Engine description:** Fires when the subject collides during forced movement.
- **Template:** `when {subject} collide{s} with a creature or object`
- **Example (subject=self, cond=`Speed > 0`):** *"When you collide with a creature or object, if the remaining speed at collision is more than 0."*
- **Status:** `OK`

### `finishmove` ("Complete Movement")
- **Engine description:** Fires when the subject finishes a movement.
- **Template:** `when {subject} finish{es} moving`
- **Example (subject=self):** *"When you finish moving."*
- **Status:** `OK`

### `forcemove` ("Force Moved")
- **Engine description:** Fires when the subject is pushed, pulled, or slid.
- **Template:** `when {subject} {is} force moved`
- **Example (subject=self, cond=`Type is "push"`):** *"When you are force moved, if the forced movement type is push."*
- **Status:** `OK`

### `fall` ("Land From a Fall")
- **Engine description:** Fires when the subject lands after falling.
- **Template:** `when {subject} land{s} from a fall`
- **Example (subject=self):** *"When you land from a fall."*
- **Status:** `OK`

### `movethrough` ("Move Through Creature")
- **Engine description:** Fires when the subject moves through another creature's square.
- **Template:** `when {subject} move{s} through another creature`
- **Example (subject=self):** *"When you move through another creature."*
- **Status:** `OK`

### `pressureplate` ("Stepped on a Pressure Plate")
- **Engine description:** Fires when the subject steps on a pressure plate.
- **Template:** `when {subject} step{s} on a pressure plate`
- **Example (subject=self):** *"When you step on a pressure plate."*
- **Status:** `OK`

### `teleport` ("Teleport")
- **Engine description:** Fires when the subject teleports.
- **Template:** `when {subject} teleport{s}`
- **Example (subject=self):** *"When you teleport."*
- **Status:** `OK`

---

## Resources & Victory band

### `earnvictory` ("Earn Victory")
- **Engine description:** Fires when the subject earns one or more victories.
- **Template:** `when {subject} earn{s} a victory`
- **Example (subject=self, cond=`Quantity >= 2`):** *"When you earn a victory, if the victories earned is at least 2."*
- **Status:** `OK` -- for resources and quantity it would be good for us to have something like "When you earn 2 victories"

### `gainresource` ("Gain Resource")
- **Engine description:** Fires when the subject gains a tracked resource.
- **Template:** `when {subject} gain{s} a resource`
- **Example (subject=self, cond=`Resource is "Focus"`):** *"When you gain a resource, if the resource is Focus."*
- **Status:** `OK` -- this would be good to be "when you gain X heroic resource" with the quantity in front, similar to victories.

### `useresource` ("Use Resource")
- **Engine description:** Fires when the subject spends a tracked resource.
- **Template:** `when {subject} spend{s} a resource`
- **Example (subject=self):** *"When you spend a resource."*
- **Status:** `OK`

---

## Turn & Game Mode band

### `prestartturn` ("Before Start of Turn")
- **Engine description:** Fires just before the subject's turn begins. Distinct from `beginturn` in ordering.
- **Template:** `just before the start of {subject-possessive} turn`
- **Example (subject=self):** *"Just before the start of your turn."*
- **Status:** `OK`

### `rollinitiative` ("Draw Steel")
- **Engine description:** DS-flavoured initiative roll event. Fires once as combat begins.
- **Template:** `at the start of combat`
- **Example:** *"At the start of combat."*
- **Note:** treated as a global event like `endcombat`; no `{subject}` placeholder. The subject filter still gates which abilities fire, but the event phrase describes the moment rather than a per-creature action.
- **Status:** `OK`

### `endcombat` ("End of Combat")
- **Engine description:** Fires once when combat ends. Global event.
- **Template:** `at the end of combat`
- **Example:** *"At the end of combat."*
- **Note:** global event, no `{subject}` placeholder.
- **Status:** `OK`

### `endrespite` ("End Respite")
- **Engine description:** Fires when a respite ends. Subject is the resting creature.
- **Template:** `when {subject} end{s} a respite`
- **Example (subject=self):** *"When you end a respite."*
- **Status:** `OK`

### `endturn` ("End Turn")
- **Engine description:** Fires at the end of the subject's turn.
- **Template:** `at the end of {subject-possessive} turn`
- **Example (subject=self):** *"At the end of your turn."*
- **Status:** `OK`

### `startdowntime` ("Start Downtime")
- **Engine description:** Fires when downtime begins. Subject is the entering creature.
- **Template:** `when {subject} start{s} downtime`
- **Example (subject=self):** *"When you start downtime."*
- **Status:** `OK`

### `beginround` ("Start of Round")
- **Engine description:** Fires once per round for each creature with a begin-round trigger. Gated by `GameSystem.HaveBeginRoundTrigger`.
- **Template:** `at the start of each round`
- **Example:** *"At the start of each round."*
- **Note:** global round event, no `{subject}` placeholder.
- **Status:** `OK`

### `startrespite` ("Start Respite")
- **Engine description:** Fires when a respite begins. Subject is the resting creature.
- **Template:** `when {subject} start{s} a respite`
- **Example (subject=self):** *"When you start a respite."*
- **Status:** `OK`

---

## Custom band

### `custom` ("Custom Trigger")
- **Engine description:** Author-defined trigger fired by `Trigger Name` / `Trigger Value` symbols.
- **Template:** `when a custom trigger fires on {subject}`
- **Example (subject=self, cond=`Trigger Name is "BeginCharge"`):** *"When a custom trigger fires on you, if the custom trigger name is BeginCharge."*
- **Status:** `OK` (note: awkward when both template and condition reference the trigger name; author will typically override via phase 7 Display field)

---

## 5e-derived trigger (ACTIVE)

### `attacked` ("Attacked") -- ACTIVE
- **Engine description:** 5e-style "I was the target of an attack roll" event. Registered only in `dnd5e.lua:864-901`, but `dnd5e.lua` does run in DS and seven compendium entries actively reference this trigger, so it ships as part of launch-tier vocabulary. If a future pass migrates those entries to a DS-native trigger and removes `dnd5e.lua`, this entry can be deleted.
- **Template:** `when {subject} {is} attacked`
- **Example (subject=self):** *"When you are attacked."*
- **Example (subject=enemy):** *"When any enemy is attacked."*
- **Status:** `OK`

---

## Aura-embedded triggers (OUT OF SCOPE)

These live in `DMHub Game Rules\Aura.lua:24,28` and apply only inside the Create Aura behaviour's embedded TriggeredAbility editor (aura-embed dispatch path falls through to the classic editor -- see design doc). Listed for awareness; **no prose work needed for the main picker**.

- `onenter` -- fires when a creature enters the aura
- `casterendturnaura` -- fires at the end of the aura caster's turn

If the aura-embed path is eventually rewritten to use the new editor, these would need their own prose entries.

---

## Summary for bake-in

1. Event prose table lives in `DMHub Utils\GoblinScriptProse.lua` (or a sibling `TriggeredAbilityProse.lua` if concerns get split later). Keyed by trigger id. Values are clause templates using placeholders from the Template rules section.
2. `GoblinScriptProse.RenderTriggerSentence(ability, options)` composes subject prose + event prose + optional condition prose and returns a full sentence. The card's Trigger row and Mechanical View's when-clause both call this.
3. Subject prose table updated (see [TRIGGER_SYMBOL_PROSE.md](TRIGGER_SYMBOL_PROSE.md) Subject section) with `role` / `possessive` forks. Composer reads whichever placeholder the template uses.
4. Placeholder substitution order: `{subject-possessive}` -> possessive form, `{subject}` -> role form, `{is}` -> `"is"`/`"are"`, `{s}` -> `""`/`"s"`, `{es}` -> `""`/`"es"`. `{is}`/`{s}`/`{es}` all use base-form (`""`/`"are"`) only when the substituted subject text is exactly `"you"` -- compound subjects starting with `"you or ..."` keep 3rd-singular agreement via the proximity rule.
5. Coverage at launch: all 42 visible triggers covered above (41 DS-native + `attacked` from `dnd5e.lua`). Comprehensive; raw-formula fallback only fires if the trigger id is unknown or the template is literally missing.

---

## Changelog

- **2026-04-24** -- Worksheet created after phase 5 verification surfaced that the auto-derived Trigger row was condition-only, missing the event + subject prose. User reviewed the card output vs the author-written `TriggeredAbilityDisplay` rendering and flagged the gap. 41 visible triggers enumerated across `TriggeredAbility.lua:167-436`, `TriggeredAbility.lua:500+`, `MCDMRules.lua:1015-1487`. Excluded hidden/deregistered triggers (`hit`, `miss`, `fumble`) and aura-embedded triggers (`onenter`, `casterendturnaura`). `attacked` retained as `DEFER` pending orphan-content dev ticket outcome.
- **2026-04-24** (rev 2) -- Voice switched to second person for `self` subject after user flagged "this creature takes damage" as developer-voice vs the player-card idiom "you take damage". Subject prose table in TRIGGER_SYMBOL_PROSE.md updated with `role` / `possessive` fork. Compound subjects (`selfandheroes`, `selfandallies`) reverted the earlier "drop the Self or" simplification -- filter inclusivity now surfaces as `"you or any ally"` / `"you or any hero"`. Template placeholder vocabulary expanded: `{s}`, `{es}`, `{is}` handle verb agreement; `{subject-possessive}` separately handles `"at the start of X's turn"` constructions.
