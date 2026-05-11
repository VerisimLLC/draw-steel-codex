# Conditions, Ongoing Effects, Riders, and Bestowed Conditions Reference

Complete technical reference for the four systems that apply status effects to
creatures in Draw Steel. Covers `CharacterCondition`, `CharacterOngoingEffect`,
`ConditionRider`, and the `bestowcondition` modifier behavior.

See also: [CORE.md](CORE.md) for UUID maps and table names.
See also: [MONSTERS.md](MONSTERS.md) for ability behaviors that apply conditions.
See also: [../../GoblinScript_Guide.md](../../GoblinScript_Guide.md) for formula syntax.

---

## Conceptual Model

Conditions are **statuses** (Frightened, Grabbed, Slowed, etc.) that carry mechanical
effects via modifiers. A condition by itself has **no inherent duration** -- it is a
named bundle of modifiers. Duration comes from HOW the condition is applied: inflicted
with a duration argument, wrapped in an ongoing effect, or bestowed by a modifier.

Four systems work together:

| System | Table | Duration Model | Typical Use |
|--------|-------|----------------|-------------|
| **Inflicted Condition** | `charConditions` | Supplied at infliction time: `"eot"` (end of turn), `"save"` (save ends), `"eoe"` (end of encounter), or `nil` (indefinite). | Named game conditions applied by abilities via power table text (e.g., "prone (save ends)"). |
| **Ongoing Effect with condition** | `characterOngoingEffects` | Turn-based duration on the ongoing effect wrapper (save ends, N rounds, end of turn, indefinite, etc.). | Ability-specific temporary effects that bestow a standard condition plus extra modifiers or custom duration. |
| **Bestowed Condition** | (computed) | Ephemeral -- exists only while the modifier that bestows it is active. No duration, no saves. | Structural game state: e.g., dying creatures are bestowed Bleeding. Disappears when the source modifier is removed. |
| **Condition Rider** | `conditionRiders` | Attached to an inflicted condition; shares that condition's lifetime unless removed first via `removeThisInsteadOfCondition`. | Extra effects layered onto a condition: "prone and can't stand (EoT)", "grabbed and can't use Escape Grab". |

### When to Use Each

- **Inflicted Condition**: For standard named conditions (Prone, Dazed, Slowed) applied
  by ability power table text. The rules engine parses tier text like `"prone (save ends)"`
  and calls `creature:InflictCondition()` with the appropriate duration.

- **Ongoing Effect with condition**: When you need custom duration, extra modifiers beyond
  what the condition provides, or caster tracking modes not supported by conditions. The
  ongoing effect wraps a condition (via its `condition` field) and delegates display
  (icon, style) to the underlying condition.

- **Bestowed Condition**: For conditions that are a structural consequence of game state
  rather than a timed effect. The global rule "Dying" uses `bestowcondition` to apply
  Bleeding to any creature at 0 Stamina -- the Bleeding condition appears with no
  duration and vanishes the moment the creature is no longer dying.

### When to Use Condition vs Ongoing Effect

**Use CharacterCondition (`charConditions` table) when:**
- The status is part of the game's shared vocabulary (players know the name)
- Multiple abilities reference it by name in power table tier text
- It appears with potency notation (e.g., `M<2 fascinated (save ends)`)
- It's a general game-rule status, not tied to one specific ability
- Examples: Bleeding, Frightened, Prone, Fascinated, Burning

**Use CharacterOngoingEffect (`characterOngoingEffects` table) when:**
- The effect is specific to one ability or narrow context
- It needs rich duration/lifecycle features (end-with-action, sustain formula, etc.)
- It wraps a condition with duration (via the `condition` field)
- It's a one-off mechanical effect, not a named game status
- Ongoing effects have MORE functionality: built-in duration system, caster tracking
  with 5 modes (none/one/set/bond/multiple), end-with-action, sustain formula,
  end trigger, emoji, hidden-from-enemies, recovery sharing
- Examples: "Quartz Shield" (bane effect from one ability), "Broken Armor" (stacking
  weakness from one ability), "Hypertensive" (one-ability debuff)

**Key difference:** Conditions are SIMPLER but more VISIBLE (they're named game terms).
Ongoing effects are MORE POWERFUL but more SPECIFIC. If something is only used by one
ability, make it an ongoing effect even if it feels like a "condition" -- the richer
feature set will serve you better.

- **Condition Rider**: For additional effects attached to a specific infliction of a
  condition. Riders are selected in ability power table text or added via the UI. They
  share the parent condition's lifetime but can intercept removal (so removing the
  condition removes the rider first instead).

---

## CharacterCondition Type (charConditions table)

Conditions are stored in the `charConditions` table (case-sensitive). Each entry is a
`CharacterCondition` game type that extends `CharacterFeature`.

### Complete YAML Field Reference

```yaml
# === Identity (required) ===
__typeName: CharacterCondition        # Must be exactly this string
id: <uuid>                            # Unique identifier for the table entry
guid: <uuid>                          # Serialization guid; must match sourceguid on all modifiers
name: "New Condition"                 # Display name shown in UI and chat

# === Content ===
description: ""                       # Rules text shown to players (plain text or YAML multiline)
iconid: "ui-icons/skills/1.png"       # Icon asset id (uuid or path); crashes if missing
display:                              # Icon display settings (required)
  bgcolor: "#ffffffff"               #   Background color (hex RGBA or LuaColor object)
  hueshift: 0                        #   Hue rotation in degrees
  saturation: 1                      #   Color saturation multiplier
  brightness: 1                      #   Brightness multiplier
emoji: "none"                         # Animated emoji id shown on token; "none" = disabled

# === Domains (required) ===
domains:                              # Must include CharacterCondition:<id>
  CharacterCondition:<id>: true       # Where <id> matches the top-level id field

# === Modifiers (required) ===
modifiers: []                         # Array of CharacterModifier objects (see Modifier Behaviors below)

# === Boolean flags ===
powertable: false                     # If true, selectable from power table tier results
stackable: false                      # If true, multiple stacks accumulate (numeric counter)
trackCaster: false                    # If true, records which creature applied the condition
indefiniteDuration: false             # If true, persists until manually removed or purged
immunityPossible: false               # If true, creatures can gain immunity to this condition
showInMenus: true                     # If true, appears in condition picker menus

# === String / formula fields ===
buffType: "debuff"                    # "debuff", "buff", or "neutral" -- affects UI grouping
implementation: ""                    # Version string (e.g. "2", "3"); engine migration marker
source: "Condition"                   # Source label displayed in modifier descriptions
sustainFormula: ""                    # GoblinScript evaluated each check; 0/false = condition ends
                                      # Example: (not Grabber.dead) where Grabber = ConditionCaster("grabbed")
maxInstancesFormula: ""               # GoblinScript on the CASTER limiting how many targets
                                      # they can apply this condition to simultaneously
                                      # Example: Maximum Grabbed Creatures

# === Caster interaction (requires trackCaster: true) ===
casterCanClick: false                 # If true, caster can click the condition icon on the target
casterClickAbility:                   # ActivatedAbility executed when caster clicks (optional)
  __typeName: ActivatedAbility
  # ... full ability definition
casterCanDrag: false                  # If true, caster can drag the affected creature

# === Underlying conditions (optional) ===
underlying:                           # Map of condition ids that auto-apply with this one
  <condition-id>: true                # Each key is an id from charConditions

# === Engine-generated (can be omitted) ===
_fork: <base64>                       # Engine-generated fork data; safe to omit
ctime: <timestamp>                    # Creation timestamp (ms since epoch)
mtime: <timestamp>                    # Last modification timestamp
```

### Key Fields Explained

**powertable**: When `true`, this condition appears as a selectable option in ability
power table tier text. The rules engine parses strings like `"M<2 prone"` and looks up
matching conditions with `powertable: true`.

**stackable**: Enables a numeric stack counter. Each infliction adds stacks (default 1).
Access via `ConditionStacks("ConditionName")` in GoblinScript. Used for damage-over-time
conditions like On Fire where damage scales with stacks.

**trackCaster**: Records the token ID and timestamp of the creature that applied the
condition. Accessed via `ConditionCaster("ConditionName")` in GoblinScript. Required for
conditions like Frightened where the bane only applies against the source of fear.

**indefiniteDuration**: The condition persists until explicitly purged by an ability
behavior (e.g., `ActivatedAbilityPurgeEffectsBehavior`) or until its `sustainFormula`
evaluates to false. Used for Grabbed, where the condition should not auto-expire.

**immunityPossible**: When `true`, the `conditionImmunities` map on a creature can
include this condition's id to make the creature immune. The immunity check fires both
during `InflictCondition` and during `bestowcondition` modifier calculation.

**sustainFormula**: A GoblinScript expression evaluated periodically. If it returns 0 or
false, the condition is automatically removed. Common pattern for Grabbed:
```
(not Source.dead) where Source = ConditionCaster("grabbed")
```
This ends the grab when the grabber dies.

**maxInstancesFormula**: Evaluated on the CASTER (not the target). Limits how many
creatures the caster can simultaneously have this condition applied to. When the limit
is exceeded, the oldest application is removed.

### GoblinScript Functions for Conditions

| Function | Returns | Context |
|----------|---------|---------|
| `ConditionCaster("ConditionName")` | The creature that applied the named condition | `activationCondition`, `conditionFormula`, `sustainFormula` |
| `ConditionStacks("ConditionName")` | Number of stacks of the named condition | Damage rolls, formulas, triggered ability behaviors |

**ConditionCaster examples:**
```
target.ConditionCaster("Frightened") = self     # Am I the source of their fear?
Self.Distance(ConditionCaster("Grabbed")) > 1   # Has the grabbed creature moved away?
(not Grabber.dead) where Grabber = ConditionCaster("grabbed")  # Sustain: ends if grabber dies
```

**ConditionStacks examples:**
```
ConditionStacks("On Fire")                      # Damage = number of fire stacks
ConditionStacks("Bleeding") + Level             # Stacks plus level
```

---

## How Conditions Get Duration

Conditions themselves have no duration field. Duration is supplied when the condition is
inflicted, via the `args` table passed to `creature:InflictCondition()`.

### creature:InflictCondition(conditionid, args)

The MCDM override (in `MCDMCreature.lua`) accepts these args:

| Field | Type | Description |
|-------|------|-------------|
| `duration` | `string` or `nil` | `"eot"` = end of turn (auto-purge, no save), `"save"` = save ends (roll at end of turn), `"eoe"` = end of encounter, `nil` = indefinite |
| `stacks` | `number` or `nil` | Number of stacks to add (default 1). Negative values remove stacks. |
| `riders` | `string[]` or `nil` | Array of condition rider IDs to attach. |
| `casterInfo` | `table` or `nil` | `{tokenid = <string>, timestamp = <number>}` -- who applied the condition. |
| `purge` | `boolean` or `nil` | If `true`, removes the condition instead of applying it. |
| `force` | `boolean` or `nil` | If `true`, overwrites existing duration even if it is `"eoe"`. |
| `sourceDescription` | `string` or `nil` | Description of what inflicted the condition (shown in UI). |
| `cast` | `ActivatedAbilityCast` or `nil` | The ability cast context, for recording. |

### How Power Table Text Flows Through

When an ability tier says `"8 damage; M<2 prone (save ends)"`, the rules engine:

1. Parses the tier text into commands
2. Recognizes `prone` as a condition with `powertable: true`
3. Checks potency: the target's Might must be < 2 for the condition to apply
4. Calls `creature:InflictCondition(proneId, { duration = "save", casterInfo = ... })`

The condition itself does not know about "save ends" -- that is a property of this
particular infliction.

---

## Save Ends Mechanic

The global rule "End Turn Save" (UUID `800867b2-86ac-4848-b95f-e147019ef22d`) fires at
the end of every creature's turn as a triggered ability.

### How It Works

1. At the end of a creature's turn, the End Turn Save trigger fires
2. For each inflicted condition with `duration = "save"`:
   - Roll `1d10 + Save Bonus`
   - If the result >= 6, the condition is purged (the "Save Ends" custom attribute
     defines the target number)
   - If the result < 6, the condition persists until the next end-of-turn check
3. For each inflicted condition with `duration = "eot"` (end of turn):
   - Auto-purge with no roll needed

### Save Penalty Modifiers

Modifiers can affect the save roll. A `power` modifier with `rollType` targeting the
save roll can add banes or edges. Some conditions or effects apply a penalty to save
rolls as part of their mechanical design.

---

## CharacterOngoingEffect with Underlying Condition

A `CharacterOngoingEffect` can wrap a standard condition via its `condition` field.

### Key Fields

```lua
CharacterOngoingEffect.condition = 'none'  -- condition id, or 'none'
```

When `condition` is set to a valid condition id:

- **Display delegation**: The ongoing effect's icon and display style come from the
  underlying condition (via `GetDisplayIcon()` and `GetDisplayDisplay()`), not from the
  effect's own icon/display fields.

- **Immunity check**: When the engine checks whether to apply the ongoing effect, it also
  checks the creature's `conditionImmunities` against the underlying condition.

- **Modifier combination**: The ongoing effect's own modifiers are applied in addition to
  (not instead of) the condition's modifiers. This lets you add extra effects on top of a
  standard condition.

### When to Use This vs. Inflicting Directly

Use an ongoing effect wrapper when you need:
- A duration model not supported by direct infliction (e.g., "N rounds from start of
  turn", "until end of next round", "until respite")
- Extra modifiers on top of the standard condition
- Caster tracking modes beyond what conditions support (`set`, `bond`, `multiple`)
- The `canEndWithAction` mechanic (spend an action to end the effect)

Use direct infliction when:
- The condition comes from power table text
- Standard durations (`"eot"`, `"save"`, `"eoe"`) are sufficient
- No extra modifiers are needed beyond what the condition definition provides

### Duration Options for Ongoing Effects

| ID | Description |
|----|-------------|
| `turn` | Until end of turn |
| `endround` | Until end of round |
| `endnextround` | Until end of next round |
| `rounds` | N rounds (from start of turn) |
| `rounds_end_turn` | N rounds (from end of turn) |
| `until_rest` | Until respite |
| `indefinite` | Indefinitely |
| `save_ends` | Save ends |
| `eoe` | End of encounter |
| `eoe_or_dying` | End of encounter or dying |

### Example: Ongoing Effect Wrapping Slowed

```yaml
_table: characterOngoingEffects
__typeName: CharacterOngoingEffect
id: <uuid>
guid: <uuid>
name: "Slowed (Custom)"
description: "This creature is slowed."
condition: "68f455f5-135f-495c-822d-40d809d2b15f"   # Slowed condition id
modifiers:
  - __typeName: CharacterModifier
    behavior: bestowcondition
    conditionid: "68f455f5-135f-495c-822d-40d809d2b15f"
    source: "Ongoing Effect"
    sourceguid: <same-as-parent-guid>
    guid: <modifier-uuid>
    name: "Slowed"
    description: ""
    domains: {}
source: "Ongoing Effect"
iconid: "ui-icons/skills/1.png"
display:
  saturation: 1
  hueshift: 0
  bgcolor: "#ffffffff"
  brightness: 1
custom: true
```

---

## Bestow Condition Modifier

The `bestowcondition` modifier behavior applies a condition ephemerally during modifier
calculation. It does not inflict the condition with a duration -- the condition exists
only as long as the modifier is active.

### How It Works

1. During `creature:CalculateModifiers()`, all active modifiers are evaluated
2. Modifiers with `behavior: bestowcondition` call `BestowConditions()`
3. The condition id is added to `_tmp_directConditions` (a transient field)
4. The creature displays the condition icon and applies the condition's modifiers
5. When the source modifier is removed, the bestowed condition vanishes instantly

### Key Characteristics

- **No duration**: There is no save, no end-of-turn check, no explicit removal
- **Immunity respected**: The bestow check consults `creature:GetConditionImmunities()`
- **Not the same as inflicting**: The condition does NOT appear in `inflictedConditions`;
  it appears in `_tmp_directConditions` only
- **Ephemeral**: Disappears the moment the source modifier is no longer active

### Pattern: Compound Conditions (Bestowing Multiple Conditions)

A condition can bestow OTHER conditions via `bestowcondition` modifiers. This is the
correct pattern for compound conditions like "Horrified = Dazed + Frightened + save penalty."
When the compound condition is removed, all bestowed sub-conditions vanish instantly.

```yaml
# Horrified bestows both Dazed and Frightened
modifiers:
  - behavior: bestowcondition
    conditionid: "<dazed-uuid>"
    name: "Horrified (Dazed)"
    ...
  - behavior: bestowcondition
    conditionid: "<frightened-uuid>"
    name: "Horrified (Frightened)"
    ...
  - behavior: power
    modtype: minustwo           # -2 save penalty
    rollType: resistance_power_roll
    ...
```

This ensures:
- All effects activate/deactivate together (no partial removal)
- The save penalty is on Horrified, not on Dazed or Frightened individually
- Standard condition immunities to Dazed or Frightened are still checked

### Example: Dying Bestows Bleeding

The global rule "Dying" (UUID `1f00c2e7-6e6a-4f23-bd3c-da4c38e35fbd`) contains a
modifier with `behavior: bestowcondition` targeting the Bleeding condition id. When a
creature reaches 0 Stamina, the Dying rule activates and bestows Bleeding. When the
creature is healed above 0, the Dying rule deactivates and Bleeding vanishes.

### YAML Structure

```yaml
- __typeName: CharacterModifier
  behavior: bestowcondition
  conditionid: <condition-id>         # id of condition to bestow from charConditions
  explanation: ""                     # Optional text shown in UI explaining why
  sourceguid: <parent-guid>
  domains:
    CharacterCondition:<id>: true     # Or appropriate domain
  source: Condition
  name: <name>
  description: <rules-text>
  guid: <modifier-guid>
```

---

## Condition Riders (conditionRiders table)

Condition riders are additional effects attached to a specific infliction of a condition.
They are stored in the `conditionRiders` table.

### Type Definition

`ConditionRider` extends `CharacterOngoingEffect` and adds:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `condition` | `string` | (inherited) | The condition id this rider belongs to |
| `removeThisInsteadOfCondition` | `boolean` | `false` | If true, removing the parent condition removes this rider first instead |
| `showAsMenuOption` | `boolean` | `false` | If true, shown as a selectable option alongside the parent condition |
| `powerTableText` | `string` | `""` | Text used in power table display for this rider |
| `allowEditingDisplayInfo` | `boolean` | `false` | Whether display info can be edited in UI |

### How Riders Work

1. An ability inflicts a condition with riders:
   ```lua
   creature:InflictCondition(conditionId, { duration = "save", riders = {riderId1, riderId2} })
   ```
2. The rider IDs are stored in the inflicted condition's `entry.riders` array
3. Each rider's modifiers are applied alongside the condition's modifiers
4. When the condition is purged, the engine checks for riders with
   `removeThisInsteadOfCondition = true` -- if found, only the rider is removed and
   the condition's duration is changed to `"eoe"` (end of encounter)

### removeThisInsteadOfCondition Mechanic

This is the "peel off" mechanic. Example: "prone and can't stand (EoT)":
- The rider "can't stand" has `removeThisInsteadOfCondition: true`
- When the creature saves against prone, instead of removing prone entirely, the
  "can't stand" rider is removed and prone continues with `duration = "eoe"`
- On the next save, prone itself is removed (no more blocking riders)

### Example Rider YAML (Cannot Stand)

```yaml
__typeName: ConditionRider
condition: da6867b1-01e3-4570-8d1b-1b94ea1ea343   # Prone condition id
name: Cannot Stand
description: This creature cannot stand up.
id: 760cf637-4f7c-42e5-9153-835111c9d87c
guid: 760cf637-4f7c-42e5-9153-835111c9d87c
removeThisInsteadOfCondition: true
showAsMenuOption: true
iconid: 4ed2da23-daf5-416c-bbc2-4e826483a00a
display:
  saturation: 1
  hueshift: 0
  bgcolor: "#ffffffff"
  brightness: 1
source: Ongoing Effect
modifiers:
- __typeName: CharacterModifier
  value: 1
  source: Ongoing Effect
  behavior: attribute
  sourceguid: 760cf637-4f7c-42e5-9153-835111c9d87c
  description: This creature cannot stand up.
  name: Cannot Stand
  attribute: 207ef4f5-948b-44b1-b3c8-feae6b14e5ce    # Custom attribute for "can't stand"
  guid: 08302814-dac1-4334-95df-3b2b6db6c5a3
```

---

## Modifier Behaviors Used in Conditions

Each modifier in a condition's `modifiers` array is a `CharacterModifier` with a
`behavior` field. Every modifier MUST have `sourceguid` matching the condition's
top-level `guid`, and `domains` containing `CharacterCondition:<id>`.

### `power` -- Edge/Bane on Rolls

```yaml
- __typeName: CharacterModifier
  behavior: power
  modtype: bane                       # "bane" or "edge"
  rollType: all                       # "all", "ability_power_roll", "enemy_ability_power_roll"
  keywords: []                        # Keyword filter (e.g. {Attack: true}); [] = all
  activationCondition: true           # GoblinScript; unquoted YAML true = always active
                                      # Use formula for conditional: target.ConditionCaster("Frightened") = self
  displayCondition: ""                # Optional; controls when the modifier shows in UI
  damageModifier: ""                  # Optional damage formula adjustment
  sourceguid: <condition-guid>
  domains:
    CharacterCondition:<id>: true
  source: Condition
  name: <condition-name>
  description: <rules-text>
  guid: <modifier-guid>
```

**activationCondition note:** Use unquoted YAML `true` for "always active". A quoted
`"true"` is a string and will be evaluated as a GoblinScript expression (which also
works but is less conventional). For conditional activation, use a formula like
`target.ConditionCaster("Frightened") = self`.

### `attribute` -- Set/Modify Numeric Attributes

```yaml
- __typeName: CharacterModifier
  behavior: attribute
  attribute: speed                    # Attribute name or custom attribute uuid
  operation: set                      # "set", "min", "add", "multiply" (default: "add")
  value: 0                            # Numeric value or GoblinScript formula string
  sourceguid: <condition-guid>
  domains:
    CharacterCondition:<id>: true
  source: Condition
  name: <condition-name>
  description: <rules-text>
  guid: <modifier-guid>
```

Common attributes: `speed`, `movementMultiplier`, or custom attribute UUIDs.
Operations: `set` forces exact value, `min` caps at minimum, `add` is additive,
`multiply` scales the value.

### `trigger` -- Triggered Ability on Game Event

```yaml
- __typeName: CharacterModifier
  behavior: trigger
  triggeredAbility:
    __typeName: TriggeredAbility
    trigger: beginturn                # Event: beginturn, endturn, useresource, move,
                                      #   useability, forcemove, teleport, takedamage, etc.
    conditionFormula: ""              # GoblinScript filter for when trigger fires
    targetType: self
    behaviors:                        # Array of ability behaviors to execute
    - __typeName: ActivatedAbilityDamageBehavior
      roll: "ConditionStacks(\"On Fire\")"
      damageType: fire
    name: <trigger-name>
    description: ""
    domains:
      CharacterCondition:<id>: true
    guid: <trigger-guid>
    # ... standard TriggeredAbility fields
  sourceguid: <condition-guid>
  domains:
    CharacterCondition:<id>: true
  source: Condition
  name: <condition-name>
  description: <rules-text>
  guid: <modifier-guid>
```

### `activated` -- Grant an Activated Ability

```yaml
- __typeName: CharacterModifier
  behavior: activated
  activatedAbility:
    __typeName: ActivatedAbility
    name: "Escape Grab"
    targetType: self
    behaviors: [...]                  # Ability behavior chain
    domains:
      CharacterCondition:<id>: true
    guid: <ability-guid>
    # ... standard ActivatedAbility fields
  sourceguid: <condition-guid>
  domains:
    CharacterCondition:<id>: true
  source: Condition
  name: <condition-name>
  description: <rules-text>
  guid: <modifier-guid>
```

### `movementtext` -- Movement Restriction Message

```yaml
- __typeName: CharacterModifier
  behavior: movementtext
  text: "You cannot shift since you are slowed."
  color: red                          # Text color in movement UI
  movementType: shift                 # Optional: restrict specific movement type
  filterCondition: ""                 # Optional GoblinScript to conditionally show
  sourceguid: <condition-guid>
  domains:
    CharacterCondition:<id>: true
  source: Condition
  name: <condition-name>
  description: <rules-text>
  guid: <modifier-guid>
```

### `suppressabilities` -- Suppress Named Abilities

```yaml
- __typeName: CharacterModifier
  behavior: suppressabilities
  explanation: "You cannot use Knockback when grabbed."
  sourceguid: <condition-guid>
  domains:
    CharacterCondition:<id>: true
  source: Condition
  name: Knockback                     # Name of the ability to suppress
  description: <rules-text>
  guid: <modifier-guid>
```

### `bestowcondition` -- Apply Another Condition

```yaml
- __typeName: CharacterModifier
  behavior: bestowcondition
  conditionid: <other-condition-id>   # id of condition to bestow from charConditions
  explanation: ""                     # Optional hover text
  sourceguid: <condition-guid>
  domains:
    CharacterCondition:<id>: true
  source: Condition
  name: <condition-name>
  description: <rules-text>
  guid: <modifier-guid>
```

---

## Templates

### Template 1: Simple Debuff (Bane on All Rolls)

A condition that applies a bane to all power rolls (like Weakened).

```yaml
__typeName: CharacterCondition
id: <uuid-A>
name: "Hexed"
description: "A hexed creature takes a bane on all power rolls."
guid: <uuid-B>
domains:
  CharacterCondition:<uuid-A>: true
iconid: "ui-icons/skills/1.png"
display:
  bgcolor: "#ffffffff"
  hueshift: 0
  saturation: 1
  brightness: 1
buffType: "debuff"
powertable: true
implementation: "3"
modifiers:
- __typeName: CharacterModifier
  behavior: power
  modtype: bane
  rollType: all
  keywords: []
  activationCondition: true
  sourceguid: <uuid-B>
  domains:
    CharacterCondition:<uuid-A>: true
  source: Condition
  name: Hexed
  description: "A hexed creature takes a bane on all power rolls."
  guid: <uuid-C>
```

### Template 2: Attribute Modifier (Speed = 0)

A condition that sets an attribute to a fixed value (like the speed component of Grabbed).

```yaml
__typeName: CharacterCondition
id: <uuid-A>
name: "Rooted"
description: "A rooted creature has a speed of 0 and cannot move."
guid: <uuid-B>
domains:
  CharacterCondition:<uuid-A>: true
iconid: "ui-icons/skills/1.png"
display:
  bgcolor: "#ffffffff"
  hueshift: 0
  saturation: 1
  brightness: 1
buffType: "debuff"
powertable: true
implementation: "3"
modifiers:
- __typeName: CharacterModifier
  behavior: attribute
  attribute: speed
  operation: set
  value: 0
  sourceguid: <uuid-B>
  domains:
    CharacterCondition:<uuid-A>: true
  source: Condition
  name: Rooted
  description: "A rooted creature has a speed of 0 and cannot move."
  guid: <uuid-C>
- __typeName: CharacterModifier
  behavior: attribute
  attribute: movementMultiplier
  operation: set
  value: 0
  sourceguid: <uuid-B>
  domains:
    CharacterCondition:<uuid-A>: true
  source: Condition
  name: Rooted
  description: "A rooted creature has a speed of 0 and cannot move."
  guid: <uuid-D>
- __typeName: CharacterModifier
  behavior: movementtext
  text: "You cannot move while rooted."
  color: red
  sourceguid: <uuid-B>
  domains:
    CharacterCondition:<uuid-A>: true
  source: Condition
  name: Rooted
  description: "A rooted creature has a speed of 0 and cannot move."
  guid: <uuid-E>
```

### Template 3: Caster-Tracking (Frightened-Style)

A condition that tracks who applied it. The caster's identity is used in activation
conditions so the bane only applies against the source of fear.

```yaml
__typeName: CharacterCondition
id: <uuid-A>
name: "Terrified"
description: "Attacks against the source of terror take a bane. The source's attacks against you gain an edge."
guid: <uuid-B>
domains:
  CharacterCondition:<uuid-A>: true
iconid: "ui-icons/skills/1.png"
display:
  bgcolor: "#ffffffff"
  hueshift: 0
  saturation: 1
  brightness: 1
buffType: "debuff"
trackCaster: true
powertable: true
stackable: true
implementation: "3"
modifiers:
# Bane on YOUR rolls targeting the caster
- __typeName: CharacterModifier
  behavior: power
  modtype: bane
  rollType: ability_power_roll
  keywords:
    Attack: true
  activationCondition: target.ConditionCaster("Terrified") = self
  sourceguid: <uuid-B>
  domains:
    CharacterCondition:<uuid-A>: true
  source: Condition
  name: Terrified
  description: "Attacks against the source of terror take a bane."
  guid: <uuid-C>
# Edge on CASTER's rolls targeting you
- __typeName: CharacterModifier
  behavior: power
  modtype: edge
  rollType: enemy_ability_power_roll
  keywords:
    Attack: true
  activationCondition: target.ConditionCaster("Terrified") = self
  sourceguid: <uuid-B>
  domains:
    CharacterCondition:<uuid-A>: true
  source: Condition
  name: Terrified
  description: "The source's attacks against you gain an edge."
  guid: <uuid-D>
```

### Template 4: Triggered Damage (Start-of-Turn with Stacks)

A stackable condition that deals damage at the start of each turn, using the stack
count as the damage value (like On Fire).

```yaml
__typeName: CharacterCondition
id: <uuid-A>
name: "Corroding"
description: "At the start of each round, take acid damage equal to the condition's stacks."
guid: <uuid-B>
domains:
  CharacterCondition:<uuid-A>: true
iconid: "ui-icons/skills/1.png"
display:
  bgcolor: "#ffffffff"
  hueshift: 0
  saturation: 1
  brightness: 1
buffType: "debuff"
stackable: true
powertable: true
implementation: "3"
modifiers:
- __typeName: CharacterModifier
  behavior: trigger
  sourceguid: <uuid-B>
  domains:
    CharacterCondition:<uuid-A>: true
  source: Condition
  name: Corroding
  description: "At the start of each round, take acid damage equal to the condition's stacks."
  guid: <uuid-C>
  triggeredAbility:
    __typeName: TriggeredAbility
    trigger: beginturn
    targetType: self
    name: Corroding
    description: ""
    numTargets: "1"
    range: 5
    repeatTargets: false
    modifiers: []
    abilityType: none
    domains:
      CharacterCondition:<uuid-A>: true
    iconid: "ui-icons/skills/1.png"
    display:
      bgcolor: "#ffffffff"
      hueshift: 0
      saturation: 1
      brightness: 1
    guid: <uuid-D>
    behaviors:
    - __typeName: ActivatedAbilityDamageBehavior
      roll: ConditionStacks("Corroding")
      damageType: acid
```

### Template 5: Indefinite with Sustain Formula (Grabbed-Style)

An indefinite condition that tracks its caster, allows the caster to click to release,
allows the caster to drag the target, and ends automatically if the source dies.

```yaml
__typeName: CharacterCondition
id: <uuid-A>
name: "Entangled"
description: "Your speed is 0. The condition ends if the source dies or you teleport."
guid: <uuid-B>
domains:
  CharacterCondition:<uuid-A>: true
iconid: "ui-icons/skills/1.png"
display:
  bgcolor: "#ffffffff"
  hueshift: 0
  saturation: 1
  brightness: 1
buffType: "debuff"
indefiniteDuration: true
trackCaster: true
casterCanClick: true
casterCanDrag: true
powertable: true
implementation: "3"
sustainFormula: (not Source.dead) where Source = ConditionCaster("Entangled")
maxInstancesFormula: "1"
casterClickAbility:
  __typeName: ActivatedAbility
  name: "Release Target"
  description: "Click to release the entangled target."
  targetType: self
  repeatTargets: false
  abilityType: none
  numTargets: "1"
  iconid: "ui-icons/skills/1.png"
  display:
    bgcolor: "#ffffffff"
    hueshift: 0
    saturation: 1
    brightness: 1
  modifiers: []
  guid: <uuid-C>
  behaviors:
  - __typeName: ActivatedAbilityPurgeEffectsBehavior
    conditions:
    - <uuid-A>
modifiers:
# Speed = 0
- __typeName: CharacterModifier
  behavior: attribute
  attribute: speed
  operation: set
  value: 0
  sourceguid: <uuid-B>
  domains:
    CharacterCondition:<uuid-A>: true
  source: Condition
  name: Entangled
  description: "Your speed is 0."
  guid: <uuid-D>
# Block all movement
- __typeName: CharacterModifier
  behavior: attribute
  attribute: movementMultiplier
  operation: set
  value: 0
  sourceguid: <uuid-B>
  domains:
    CharacterCondition:<uuid-A>: true
  source: Condition
  name: Entangled
  description: "Your speed is 0."
  guid: <uuid-E>
# Movement warning text
- __typeName: CharacterModifier
  behavior: movementtext
  text: "You cannot move while entangled."
  color: red
  sourceguid: <uuid-B>
  domains:
    CharacterCondition:<uuid-A>: true
  source: Condition
  name: Entangled
  description: "You are entangled."
  guid: <uuid-F>
# End on teleport
- __typeName: CharacterModifier
  behavior: trigger
  sourceguid: <uuid-B>
  domains:
    CharacterCondition:<uuid-A>: true
  source: Condition
  name: Entangled
  description: "Teleporting ends the entangle."
  guid: <uuid-G>
  triggeredAbility:
    __typeName: TriggeredAbility
    trigger: teleport
    targetType: self
    name: Entangled
    description: ""
    numTargets: "1"
    range: 1
    repeatTargets: false
    modifiers: []
    abilityType: none
    domains:
      CharacterCondition:<uuid-A>: true
    iconid: "ui-icons/skills/1.png"
    display:
      bgcolor: "#ffffffff"
      hueshift: 0
      saturation: 1
      brightness: 1
    guid: <uuid-H>
    behaviors:
    - __typeName: ActivatedAbilityPurgeEffectsBehavior
      conditions:
      - <uuid-A>
```

---

## Key Notes and Pitfalls

1. **guid must match sourceguid on all modifiers.** The condition's top-level `guid` must
   be the same value used as `sourceguid` on every modifier in the `modifiers` array.
   Mismatched guids cause modifiers to be silently ignored.

2. **domains must include `CharacterCondition:<id>`.** Both the condition itself and every
   modifier must have this domain entry. The `<id>` is the top-level `id` field value.

3. **Table name is `charConditions` (case-sensitive!).** Not `CharacterConditions`, not
   `charconditions`. The Lua code uses `CharacterCondition.tableName` which resolves to
   exactly `"charConditions"`.

4. **`_fork` can be omitted.** The engine generates this field automatically. You do not
   need to provide it in YAML definitions.

5. **`activationCondition`: use unquoted YAML `true` for "always".** Do not quote it as
   `"true"`. Unquoted `true` is a YAML boolean that the engine interprets as "always
   active". For conditional activation, use a GoblinScript formula string.

6. **`implementation` is a version marker.** When the engine or codex upgrades condition
   logic, this field tracks which version the condition was last migrated to. New
   conditions should use the latest value (currently `"3"`).

7. **Condition riders table is `conditionRiders`** (case-sensitive). The rider's
   `condition` field must contain a valid condition id from `charConditions`.

8. **Bestowed conditions are NOT inflicted.** They do not appear in
   `inflictedConditions` -- they live in the transient `_tmp_directConditions` field and
   vanish when the bestowing modifier is removed.

9. **Stacking behavior differs between conditions and ongoing effects.** Conditions with
   `stackable: true` accumulate a numeric counter (additive). Ongoing effects with
   `stackable: true` use `clearStacksWhenApplying` to choose between additive
   (`false`) and max-of-existing (`true`).
