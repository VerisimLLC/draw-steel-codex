# GoblinScript Docs Audit

Findings from cross-checking the existing reference docs against the actual
source. Each section calls out a class of issue. **Nothing in the existing
docs has been edited;** this is a list of what to fix later.

Files audited:
- `compendium/reference/GOBLINSCRIPT-SYMBOLS.md`
- `compendium/reference/GOBLINSCRIPT-ABILITY-SYMBOLS.md`
- `compendium/reference/GOBLINSCRIPT-CONTEXTS.md`
- `compendium/reference/GOBLINSCRIPT-ALL-TYPES.md`
- `GoblinScript_Guide.md` (top-level)

Cross-checked against:
- `D:/dev/dmhub/Assets/Scripts/GoblinScript.cs` (the C# parser)
- `DMHub Utils/GoblinScript.lua` (Lua wrapper)
- All `RegisterSymbol`, `RegisterGoblinScriptField`, `RegisterGoblinScriptSymbol`,
  `helpSymbols`, `lookupSymbols` definitions in `DMHub Game Rules/`,
  `Draw Steel Core Rules/`, and other top-level codex directories.

---

## A. Symbols documented but NOT registered (stale docs)

These appear in the reference docs but I could find no `lookupSymbols`
entry implementing them. They will silently return `nil` (becomes 0 in
arithmetic) at runtime.

### A.1 `Subclasses` -- creature

Listed in `GOBLINSCRIPT-SYMBOLS.md` row 45 and in `creature.helpSymbols`
(`Creature.lua:7280-7284`), but no `lookupSymbols.subclasses` entry exists.
Calling `Self.Subclasses` returns `nil`.

**Fix:** either add a lookupSymbols entry that returns a StringSet of
subclass names, or remove the help entry.

### A.2 `Cantrip` -- ability

Has a `lookupSymbols.cantrip` entry (`ActivatedAbility.lua:5095`) but no
`helpSymbols.cantrip` entry. It works at runtime but is invisible to
autocomplete and the GoblinScript editor. (D&D leftover -- in DS this is
always false.)

### A.3 `school` -- ability

Same as Cantrip -- only `lookupSymbols.school` (`ActivatedAbility.lua:5099`),
no help entry. D&D leftover.

### A.4 `weight` -- creature (verified -- actually registered)

`weight` is documented in `GOBLINSCRIPT-SYMBOLS.md` row 135. **Verified
present** at `MCDMCreature.lua:2206` -- not stale, but easy to miss because
it lives in MCDMCreature rather than the base lookupSymbols block.

### A.5 `Resources.Standard Action` examples

The `Resources` documentation (`GOBLINSCRIPT-SYMBOLS.md:94`) gives
`Resources.Standard Action > 0` as the example. This relies on the resource
table containing an entry named "Standard Action". If that entry is renamed
or hidden in `tables/characterresources/`, the symbol silently disappears.
**No issue today,** but worth a note in the doc that this is dynamic.

---

## B. Symbols registered but NOT documented (missing from docs)

### B.1 Creature symbols missing from `GOBLINSCRIPT-SYMBOLS.md`

| Symbol | Source | Importance |
|---|---|---|
| `In Difficult Terrain` | `MCDMCreature.lua:2939` | High -- gates Charge bonuses, reach. |
| `OnGround` | `MCDMCreature.lua:4955` | Medium -- companion to InWater. |
| `Distance Below Ground` | `Creature.lua:6962` | Medium -- for burrowing/swimming creatures. |
| `Floor Altitude` | `Creature.lua:6955` | Medium -- comparisons across floors. |
| `Always` | `Creature.lua:lookup 7587` | Low -- diagnostic constant 1. |
| `Never` | `Creature.lua:lookup 7591` | Low -- diagnostic constant 0. |
| `EoT Effects` | `MCDMCreature.lua:1603` | Medium. |
| `Has Adjacent Enemy Other Than Us` | `MCDMRules.lua:554` | High -- common for OA logic. |
| `Is Friend` | `MCDMRules.lua:582` | High -- redundant with `Friends(...)` global but documented separately. |
| `Persistent Abilities` | `AbilityPersistentCast.lua:23` | Medium -- talent/persistence content. |
| `Number of Persistent Abilities` | `AbilityPersistentCast.lua:12` | Medium. |
| `Stability` | `MCDMRules.lua:601` | High -- referenced in many YAMLs. |
| `Short Name` | `MCDMCreature.lua:5102` | Low. |
| `Magic Treasure Count` | `MCDMCreature.lua:1295` | Low. |
| `numberoftargets` -- the bare-context ability symbol -- under-documented for
   the **cast-level** `Cast.Target Count`. People reach for `numberoftargets`
   on the ability and miss `Cast.Target Count` (which is what they actually
   want to read at runtime). |
| `Effect Caster` (creature symbol) | `MCDMCreature.lua:3519` | High -- present in
  `GOBLINSCRIPT-SYMBOLS.md:173` as `Effect Caster`. Verified registered. |
| `Boons`, `Banes` (cast) | `MCDMActivatedAbilityCast.lua:12,24` | High. Documented
  in ABILITY-SYMBOLS but not in GOBLINSCRIPT-SYMBOLS table. |

### B.2 Built-in functions missing from prose

`Substring(haystack, needle)` is registered in C# (`GoblinScript.cs:3313`)
but `GoblinScript_Guide.md` Section 7 only lists `min`, `max`, `floor`,
`ceiling`, `Friends`, `Line of Sight`. Substring is documented in the
all-types doc but not in the guide.

`Line of Sight` accepts an optional **third argument** `pierceSurfaces`
(`GoblinScript.cs:3247`) -- not mentioned anywhere in the existing docs.

### B.3 The `__is__` special key

The `is` and `has` operators dispatch to a creature/object's `__is__`
function when the LHS is a function/table. This is how `Conditions has
"Prone"` and `Type is Goblin` actually work
(`Creature.lua:8278-...`, `GoblinScript.cs:2412-2424`).

Not mentioned in the language guide. If a content author adds a custom
"set-like" object via `RegisterSymbol`, they need to know to implement
`__is__` for membership.

### B.4 Compound `is` against bare identifiers

`Type is Goblin` (no quotes) is supported -- the parser falls back to
treating an unresolved identifier on the RHS of `is`/`has` as a literal
string (`GoblinScript.cs:2351-2360`). Documented sparsely; the guide
shows examples both with and without quotes but does not say the rule.
This trips people up because **`=` does not have the same fallback**:
`Type = Goblin` won't work; you need `Type = "Goblin"` or `Type is Goblin`.

### B.5 Cast extensions on Attack-related rolling

`MCDMAttack.lua:5-15` registers `highestnumberonattackdice` on
ActivatedAbilityCast for d6-attack systems. Listed in
`GOBLINSCRIPT-ABILITY-SYMBOLS.md:148` but not in
`GOBLINSCRIPT-SYMBOLS.md`.

### B.6 TierSymbols pseudo-type

`MCDMAbilityRollBehavior.lua:2169-2180` defines `includesforcedmovement`,
`push`, `pull`, `slide` on a tier object. Used in tier-text power roll
modifiers. Documented in `GOBLINSCRIPT-ABILITY-SYMBOLS.md:353-368` but
hard to reach without an example call site.

### B.7 Forced movement sub-symbols on Cast

`Forced Movement Damage Dealt to Targets` (note the "to Targets" suffix)
exists on Cast (`ActivatedAbilityCast.lua:256`, `lookup 495`). Documented
in `GOBLINSCRIPT-ABILITY-SYMBOLS.md:130` but easy to miss.

### B.8 `NumAttackers` was added recently

`Cast.NumAttackers(Target)` (`MCDMActivatedAbilityCast.lua:103`, line
referenced in commit `607cf70`). NOT in any existing reference doc.

---

## C. Wrong / misleading descriptions in existing docs

### C.1 `Power Roll Bonus` description

`GOBLINSCRIPT-SYMBOLS.md:93`: "Bonus that monsters get to their power
rolls. Zero for heroes."

**Verified correct.** Implementation at `MCDMCreature.lua:3622` calls
`c:PowerRollBonus()` and the monster override at `MCDMMonster.lua:24`
returns the per-monster bonus; the creature default returns 0.

### C.2 `Hidden This Turn` location wrong

`GOBLINSCRIPT-SYMBOLS.md:154` puts it in the "Combat Status" table and
attributes it to `Creature.lua (helpSymbols)`. The lookup actually keys on
a `_tmp_hiddenTurnId` field set during the hidden state machine
(`Creature.lua:7401`, `lookup 8170`), and only matches when the current
initiative turn id matches the hidden id. Useful detail missing from the
doc.

### C.3 `Conditions` includes inflicted + bestowed

`GOBLINSCRIPT-SYMBOLS.md:166`: "Names of active conditions."

That's true but understates it. `lookup 7964` aggregates THREE sources:
inflicted conditions, ongoing-effect-derived conditions, and
bestowed/calculated conditions from modifiers. The doc should call this out
because it surprises people who expect "just the conditions list".

### C.4 `Mode` documentation is split

`Cast.Mode` (`ActivatedAbilityCast.lua:60`) and the casting-context `mode`
(`ActivatedAbility.lua:5212`) are different things:
- `Cast.Mode` -- snapshot of mode on the in-progress cast.
- bare `mode` -- the casting-context's mode argument, not on the cast
  object.

In practice they hold the same value. The docs treat them
interchangeably which is slightly misleading.

### C.5 `Or` returning numeric max is buried

`GoblinScript_Guide.md` Section 2 mentions it. The fact is critical for
formulas like `min(MaxStamina, Stamina + Heal or Recovery Value)` and
should be flagged more prominently in the language reference, not only
the prose guide.

### C.6 `MCDModifyPowerRolls.lua` filename in CONTEXTS doc

The contexts doc cites `MCDModifyPowerRolls.lua` (single-D) for line
references. The actual file is `MCDModifyPowerRolls.lua` -- verified, that
is the actual filename (no extra D). **Not stale.** Mentioned for
completeness because it looks like a typo at first glance.

### C.7 `PassesPotency` argument signature in old doc

`GOBLINSCRIPT-ABILITY-SYMBOLS.md:139` shows
`Cast.PassesPotency(Target, "P", "Strong")` and `Cast.PassesPotency(Target,
"M")`. **Verified correct** by reading
`MCDMActivatedAbilityCast.lua:36-77`. The third arg can be a string
(`"weak"`/`"average"`/`"strong"`), a number, or omitted (uses tier
fallback).

### C.8 `Effect Caster` returns boolean, not stack count

`GOBLINSCRIPT-SYMBOLS.md:173`: "returns stacks of that effect cast by a
specific creature."

**Wrong.** The implementation at `MCDMCreature.lua:3519-3573` accumulates
stacks then returns `result > 0` -- a boolean. To get the stack count from
a specific caster you'd need a different symbol, which doesn't exist.

### C.9 `Condition Stacks` returns conditions OR ongoing effects

`GOBLINSCRIPT-SYMBOLS.md:169` describes it as "stack count of a named
condition." The implementation (`MCDMCreature.lua:3576-3614`) checks
inflictedConditions FIRST, then sums ongoing effect stacks of matching
name as a fallback. So it conflates condition stacks and ongoing-effect
stacks. May surprise someone who expects only conditions.

### C.10 `firsttarget` and `Primary Target` are distinct on Cast

Both `Cast.First Target` and `Cast.Primary Target` exist. They look
synonymous but `firsttarget` returns `c.targets[1]` directly
(`ActivatedAbilityCast.lua:285`), while `primarytarget` walks targets
looking for one with a non-nil token (`lookup 415`). Subtle difference for
abilities with location-only targets.

### C.11 `Charges` documented in casting context only

`GOBLINSCRIPT-ABILITY-SYMBOLS.md:48` lists it under casting context, but
it's also referenced as a parameter to `mode` and `upcast` formulas. The
docs don't say where it comes from -- it's an `options.symbols.charges`
value injected by the cast pipeline.

---

## D. Context (LookupSymbol-binding) discrepancies

### D.1 `filterTarget` Self varies

`GOBLINSCRIPT-CONTEXTS.md:228-247` correctly notes that `filterTarget`'s
Self is normally the **target creature**, but for location-targeted
abilities the Self is the **caster**. Verified at
`ActivatedAbility.lua:1112` vs `1241`. Important caveat -- no objection.

### D.2 `activationCondition` on power-roll modifier sees more than docs say

The docs say `activationCondition` sees `Self`, `Ability`, `Target`,
`Title`, plus modifier symbols. Reading
`MCDMAbilityRollBehavior.lua:911` and the modifier filter pipeline shows
that the `options.symbols` table also gets `cast`, `caster`, `target`,
`mode`, `targetPairs` (for minion squad coordination). So
`activationCondition` can read `Cast.Tier`, `Cast.Damage Dealt`, etc.,
mid-roll. Useful but undocumented.

### D.3 `displayCondition` vs `activationCondition`

`displayCondition` runs BEFORE the roll (no roll data). `activationCondition`
runs DURING the roll (Cast may have partial data). This distinction is in
the contexts doc but not flagged loudly enough. People sometimes use Cast
fields in displayCondition expecting them to be set.

### D.4 Trigger context Resource string

The `useresource`/`gainresource` triggers expose `Resource` as a string
(`GOBLINSCRIPT-CONTEXTS.md:195`). Memory file documents that the value is
the **internal** name "Heroic Resource", not the class display name
("Ferocity" / "Insight" / etc.). Worth surfacing in CONTEXTS doc since it
is a frequent gotcha.

### D.5 Aura context `Aura.Caster` is the only field

`GOBLINSCRIPT-ABILITY-SYMBOLS.md` correctly lists `caster` as the only
aura field. There is **no** `Aura.Name`, `Aura.Range`, etc., despite
authors expecting them. If you want aura name in a filter, you'd need a
new symbol registered.

---

## E. Operator / parser facts missing from guides

These are not symbol issues but parser semantics that the prose guide
doesn't cover:

1. **Identifier merging** -- adjacent identifiers with whitespace become
   one. The guide hints but doesn't make it clear that `Maximum   Stamina`
   (extra spaces) and `MaximumStamina` (no space) are the same lookup.
2. **Keyword-eats-identifier** -- `is`, `has`, `not`, `and`, `or`, `when`,
   `else`, `where` are reserved tokens. A symbol named e.g. `Andersen`
   will be tokenized as `And`+`ersen` and break.
3. **Division is integer (floored)** -- `7/2 = 3`, not `3.5`. The
   compiler emits `math.floor`. Important when authors expect fractional
   distance/damage.
4. **String compare normalization** -- `=` between two strings strips ALL
   whitespace before compare. `"Power Roll" = "powerroll"` is true.
5. **`or` returns max for two numbers** -- not just boolean. See C.5.
6. **`when` defaults to 0** when condition is false and no `else` is
   given. The prose guide says this in Section 12, but the failure mode
   for "I forgot the `else`" is silent zero, not a runtime warning.
7. **Compilation failures cache as `false`** -- a typo in a formula
   permanently degrades to `defaultValue` until `/flushcompiledgoblinscript`
   is run. Worth documenting.
8. **Recursion cap of 10** -- `GoblinScript.cs:512`. Hit this when one
   formula triggers another that triggers the first, etc. Returns 0.
9. **Non-deterministic dice keywords are stripped in deterministic mode.**
   Most codex compile sites are deterministic, so dice expressions like
   `2d10 keep high` only work in roll-string contexts.

---

## F. Symbols that need clarification for common author questions

The user asked specifically about these speculative cases. Here's the
verified answer:

### F.1 "Number of targets in this cast"

**Use `Cast.Target Count`** (`ActivatedAbilityCast.lua:190,426`).

`Number of Targets` (bare, on the Ability) returns the **maximum** number
of targets the ability can have, not the number actually targeted in the
running cast.

### F.2 "Is creature X in the area of this cast"

**`Cast.HasTarget(X)`** (`ActivatedAbilityCast.lua:185,307`). Walks the
running targets list. Works for any target type (not specifically area).
There is no separate "in area" predicate -- the engine resolves area
membership before adding to targets, so by the time your formula runs the
list IS the area-affected creatures.

### F.3 "Is creature X adjacent to creature Y"

No direct symbol. Compose:
- From X's perspective: `X.Distance(Y) <= 1` -- `Distance` returns
  squares (`Creature.lua:7833`).
- For "adjacent enemy other than ourselves":
  `X.Has Adjacent Enemy Other Than Us(Self)` (`MCDMRules.lua:554`).
- For "X is being flanked by Y": `X.Flanked By(Y)` (`MCDMCreature.lua:1643`).

### F.4 "Is target winded / dying / at <= 0 stamina"

- **Dying:** `Target.Dying` -- registered (`MCDMCreature.lua:1140`).
- **Dead:** `Target.Dead` -- registered (`MCDMCreature.lua:1406`).
- **Winded:** **NOT registered as a symbol.** Use the derived expression
  `Target.Stamina <= 0` (winded means at or below 0 stamina in DS rules).
  The implementation method `c:IsWinded()` exists at
  `MCDMCreature.lua:4090`+ but is not exposed.
- **At <= 0 stamina:** `Target.Stamina <= 0`.

`[FLAG]` Add `Winded` and `Bloodied` as registered symbols. Easy fix in
`MCDMCreature.lua` next to `dying`/`dead`. Until then, work around with
direct stamina comparisons.

### F.5 "Intuition score of caster's companion"

There is **no `Companion` symbol registered**. The Beastheart code
(`Draw Steel Beastheart/`) adds zero `RegisterSymbol` calls. The companion
is represented as a separate token whose summoner is the Beastheart hero.

To get from Beastheart (caster) to companion: there isn't a direct way in
GoblinScript. From the **companion** side, `Self.Summoner` returns the
Beastheart (`Creature.lua:7868`). So in formulas evaluated on the
companion, `Summoner.Intuition` works. In formulas evaluated on the
Beastheart, no symbol points to the companion.

`[FLAG]` Should register a `Companion` symbol on creatures (returns the
single companion if any, else nil). Currently authors must rely on
filter-driven `Count Nearby Friends(...)` shenanigans or wire up symbols
manually via the PowerTableTriggers caster/target binding.

---

## G. Suggested edits (prioritized)

1. Add `Winded`, `Bloodied`, `Companion` symbols to creature.
2. Add `helpSymbols.cantrip`, `helpSymbols.school` for ability (or remove
   the lookups -- they're D&D leftovers).
3. Fix `Effect Caster` description to say "boolean" instead of "stacks".
4. Document the third arg to `Line of Sight`.
5. Document `__is__` and the bare-identifier-on-RHS-of-`is` rules.
6. Add `In Difficult Terrain`, `OnGround`, `Stability`,
   `Has Adjacent Enemy Other Than Us`, `Persistent Abilities`,
   `Cast.NumAttackers`, `Cast.Boons`, `Cast.Banes` to the main symbols
   table.
7. Note the deterministic-vs-non-deterministic distinction and keyword
   stripping in the LANGUAGE doc.
8. Add the "compilation failure caches as `false` until flush" note to the
   troubleshooting section of the guide.
9. Note that `Resources.<Name>` is the only way to access resources by
   name -- bare `<Name>` does NOT work.
10. Note that `Subclasses` has a help entry but no lookup, so it always
    returns nil.

These are docs-only changes; no Lua/C# code is required for the docs to be
correct. The flagged items in F.4 and F.5 (`Winded`, `Companion`) require
actual code changes.
