# Power Table Text Parsing Reference

When an ability has `ActivatedAbilityPowerRollBehavior`, the tier text strings are
automatically parsed and executed at runtime. This document catalogs EVERY pattern
that is recognized and auto-handled.

---

## Processing Pipeline

1. **GoblinScript substitution** -- `{expression}` in curly braces evaluated first
2. **HTML/rich-text stripping** -- tags removed; `<alpha=#00>` = stop-parsing marker
3. **Characteristic normalization** -- `7 + M damage` pre-resolved to a number
4. **Potency gate extraction** -- `M<2` gates evaluated against the target
5. **Compendium patterns** (`importerPowerTableEffects` table) -- checked first (longest match wins)
6. **Built-in `g_rulePatterns`** -- hardcoded regex rules checked second
7. **Dynamic patterns** -- condition riders, resources, conditions from data tables
8. **Tail recursion** -- after a match, remainder after `;`, `,`, `and`, `then` is recursively parsed

The `#` character marks unimplemented text (dimmed in UI, skipped during execution).

---

## Built-in Patterns (MCDMAbilityBehavior.lua)

### Damage

```
X damage                    -- untyped damage
X type damage               -- typed damage (fire, cold, etc.)
X damage (half)             -- halved damage (stackable)
2d6 + 3 damage              -- dice roll (opens roll dialog)
7 + M, A, or I fire damage  -- characteristic bonus (highest of listed)
```

- `(half)` can stack: `(half) (half)` = quarter damage
- Dice expressions (`d`, `+`, `-`) open a roll dialog
- Characteristic letters: M=Might, A=Agility, R=Reason, I=Intuition, P=Presence
- `{GoblinScript}` in curly braces evaluated before parsing

### Forced Movement

```
push X                              -- push X squares
pull X                              -- pull X squares
slide X                             -- slide X squares
vertical push X                     -- vertical push
vertical pull X                     -- vertical pull
vertical slide X                    -- vertical slide
push straight up X                  -- push straight up
push X, ignoring stability          -- ignores target stability
push X; this push ignores the target's stability  -- same
```

- Stability automatically subtracted from distance
- "Big vs Little" bonus: +1 if melee weapon strike and caster size > target size
- "Forced Movement Increase/Bonus" custom attributes applied
- "Cannot Be Force Moved" attribute blocks all forced movement
- Grabbed targets cannot be force moved (unless by the grabber)

### Conditions with Duration

```
dazed (eot)                         -- end of target's next turn
slowed (save ends)                  -- save ends
bleeding (eoe)                      -- end of encounter
frightened of you (eot)             -- "of you" normalized away
dazed and slowed (save ends)        -- multiple conditions
bleeding, weakened (eot)            -- comma-separated
taunt (eot)                         -- normalized to "taunted"
```

Recognized conditions: `bleeding`, `dazed`, `frightened`, `frightened of you`,
`grabbed`, `prone`, `restrained`, `slowed`, `taunted`/`taunt`, `weakened`

Also matches ANY condition with `powertable = true` in the `charConditions` table,
and any condition rider from the `conditionRiders` table.

### Prone and Grabbed (bare)

```
prone                               -- applies prone (EoE duration)
grabbed                             -- applies grabbed (EoE duration)
prone and can't stand (save ends)   -- prone + cannot stand rider
prone can't stand (eot)             -- same, without "and"
```

### Condition State Changes

```
prone persists                      -- no-op (condition continues)
dazed ends at the end of your next turn  -- sets EoT duration
frightened immediately ends         -- purges the condition
```

### Caster Movement (executed on "caster pass")

```
shift X                             -- caster shifts up to X squares
you can shift X                     -- same
you shift X                         -- same
shifts up to X                      -- same
the caster shifts X squares         -- same

teleport X                          -- caster teleports up to X squares
you teleport X                      -- same
teleports up to X squares           -- same

jump X                              -- caster jumps up to X squares
```

- Shift blocked if "Shift Disabled" > 0
- Movement capped by remaining speed

### Resources

```
gain X piety                        -- heroic resource (any: piety, essence, etc.)
gain X surges                       -- or any named resource from table
the target gains X surges           -- target gains surges
target gains one surge              -- word numbers supported (one-ten)
the director gains X malice         -- adds to global malice counter
```

### Special

```
swap places with the target         -- position swap
teleport to opposite side           -- teleport target to opposite side of caster
free strike or grabbed if adjacent  -- conditional: free strike OR grabbed
a new target in reach takes X damage           -- redirect damage (caster pass)
a new target in range takes X type damage      -- same, typed
```

### Potency Gates

```
M<2 prone (save ends)               -- if target Might < 2, apply prone
R<3 dazed (eot)                     -- if target Reason < 3, apply dazed
A<5 slowed, weakened (save ends)    -- gate multiple effects
M < [weak]                          -- gate = caster highest char - 2
M < [average]                       -- gate = caster highest char - 1
M < [strong]                        -- gate = caster highest char
```

Gate values have caster's "Potency Bonus" custom attribute added.
Target's active modifiers with `resistanceFormula` adjust effective resistance.

---

## Importer Power Table Effects (compendium/tables/importerpowertableeffects/)

These 42 patterns are checked BEFORE built-in rules. They use `<<placeholder>>`
syntax: `<<num>>`, `<<amount>>`, `<<distance>>`, `<<range>>`, `<<count>>` match
numbers/words; `<<monster>>` matches creature names; `<<surges>>` matches surge icons.

### Damage Effects

| Pattern | Effect |
|---------|--------|
| `This ability deals an additional <<num>> damage if the target is within <<distance>> squares of the <<monster>>` | Extra damage if target near caster |
| `Lightning damage equal to <<amount>> + your level` | Level-scaling lightning damage |

### Forced Movement Extensions

| Pattern | Effect |
|---------|--------|
| `slide <<number>>; the slide is vertical` | Converts to vertical slide |
| `the forced movement is vertical` | Makes any forced movement vertical |
| `Teleport the target <<distance>>` | Teleports target (not caster) |

### Ally Actions

| Pattern | Effect |
|---------|--------|
| `An ally within <<range>> can spend a recovery` | Ally heals via recovery |
| `an ally within <<range>> can spend a Recovery and has a +1 on the next attack...` | Recovery + edge |
| `<<count>> allies within <<range>> shift <<distance>> squares` | Allies shift |
| `ally adjacent to target can make a free strike against them` | Allied free strike |
| `an ally within <<range>> can make an opportunity attack against the target...` | Allied opportunity attack |
| `an ally within <<range>> can make an opportunity attack with a +1...` | OA with edge |
| `a hero within range can make a save` | Hero makes a save (Hermit) |

### Ongoing Effects (applied to target)

| Pattern | Effect |
|---------|--------|
| `<<monster>> takes a bane on their next attack` | Bane on next attack |
| `<<monster>> takes a bane on their next power roll` | Bane on next power roll |
| `<<monster>> has a double bane on their next power roll` | Double bane |
| `the next attack against the target has a +1` | +1 to next attack vs target |
| `the next attack against the target has a +2` | +2 to next attack vs target |
| `the next attack against the target has <<surges>>` | Surges on next attack vs target |
| `The target's next attack has <<surges>>` | Surges on target's next attack |
| `the target is illuminated (save ends)` | Illuminated condition |
| `the target is shapechanged (save ends)` | Shapechanged condition |
| `<<monster>> goes out of phase` | Out of phase effect |
| `<<monster>> is flung through time` | Flung through time effect |
| `the target is frightened of an ally of your choice within range (save ends)` | Frightened of ally |
| `each enemy within <<squares>> squares of them is frightened of you (save ends)` | AoE frightened |
| `the target gains <<amount>> rage` | Inflict rage stacks |
| `stability reduced by <<amount>> (EoT)` | Stability reduction |
| `Foesense` | Foesense effect |

### Weakness Effects

| Pattern | Effect |
|---------|--------|
| `the target has acid weakness <<number>> (save ends)` | Acid weakness |
| `the target has corruption weakness <<number>> (save ends)` | Corruption weakness |
| `the target has damage weakness <<amount>> (save ends)` | Generic damage weakness |
| `the target has fire weakness <<number>> (save ends)` | Fire weakness |

### Self/Caster Effects

| Pattern | Effect |
|---------|--------|
| `you gain damage immunity <<amount>> until the end of your next turn` | Damage immunity |
| `(The target/You) gains <<amount>> temporary Stamina` | Temporary stamina |
| `you and each ally adjacent to you gain <<amount>> temporary Stamina` | AoE temp stamina (UNIMPLEMENTED) |
| `The Director gains <<amount>> Malice` | Director gains malice |
| `choose and use a domain effect` | Conduit domain effect |
| `Gain <<amount>> Heroic Resources, which you can keep or distribute...` | Troubadour resources |

### Modifier Effects

| Pattern | Effect |
|---------|--------|
| `<<monster>> has an edge on this ability while adjacent to an ally` | Edge modifier |
| `If the target deals damage..., the target takes another 1d10 lightning damage (save ends)` | Retaliatory damage |

---

## What This Means for Monster Automation

If a monster's ability has `ActivatedAbilityPowerRollBehavior` with tier text, ALL of
the above patterns are automatically handled at runtime. This means:

**Already fully automated from tier text alone:**
- All damage (typed and untyped, with dice, characteristics, halving)
- All push/pull/slide (with stability, size bonuses, grabbed checks)
- All standard conditions with durations (dazed, slowed, bleeding, etc.)
- All potency gates (M<2, R<3, etc.)
- Caster shift/teleport/jump
- Heroic resource gains, surges, malice
- Ally recovery, ally shift, ally free strikes
- Bane/edge effects on next attacks
- Weakness application
- Temporary stamina
- Many special effects (illuminated, shapechanged, out of phase, etc.)

**NOT auto-handled (requires additional behaviors or Lua):**
- Summoning creatures
- Creating terrain/zones/walls on the map
- Multi-ability combos ("use X then use Y")
- Damage halving/redirection reactions
- Death triggers ("when reduced to 0 stamina")
- Faction-wide buffs ("each demon gains double edge")
- State changes (stance switching, form changing)
- Custom movement modes (burrowing, phasing)
- Object creation/manipulation
- Counting mechanics ("for each adjacent ally")

**The `#` marker**: Text after `#` is display-only and not parsed. If you see
`8 damage; push 3 # and the target drops what it's holding`, the damage and push
execute but the drop-item effect is informational only.
