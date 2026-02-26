# Timeline Module

The Timeline module implements the **ability sidebar** -- the UI that appears on the right side of the screen when an ability is previewed or actively being used. It steps the user through each stage of ability execution: displaying the ability description, rolling dice, choosing modifiers/triggers, consuming resources, and resolving effects.

Module ID: `7e183326-815e-4e5a-8d81-af4f5d23e083` (loaded as `Timeline_e083`)

## Files

| File | Purpose |
|---|---|
| `TimelineMain.lua` | Stub entry point (just acquires `mod`). Currently empty of logic. |
| `AbilitySidebar.lua` | Manages the ability display panel on the right side of the HUD. Shows/hides the ability tooltip card and handles section highlighting during execution. |
| `EmbeddedRollDialog.lua` | The main roll prompt dialog. When a dice roll is needed (power rolls, damage, etc.), this creates an interactive UI embedded inside the ability sidebar that lets the user configure modifiers, edges/banes, surges, and triggers before rolling. |

## How It Works

### Ability Display Lifecycle

1. **Show ability**: When an ability is activated, `CharacterPanel.DisplayAbility(token, ability, symbols)` is called. This fires the `showAbility` event on the ability display panel, which renders the ability tooltip card (via `CreateAbilityTooltip` or a trigger-specific renderer).

2. **Embed roll dialog**: `CharacterPanel.EmbedDialogInAbility()` creates a new embedded roll dialog (via `GameHud.CreateEmbeddedRollDialog()`) and fires `embedRollDialog` to insert it into the ability display panel. The roll dialog appears inline within the ability card.

3. **Roll interaction**: The roll dialog's `ShowDialog(options)` method is called with configuration for the roll (formula, modifiers, targets, roll properties, callbacks). The user interacts with the dialog to adjust modifiers and roll dice.

4. **Section highlighting**: As the ability execution coroutine progresses through behaviors, `CharacterPanel.HighlightAbilitySection(options)` is called with `section = "target"`, `"main"`, or `"effects"` to visually indicate which part of the ability card is currently active.

5. **Hide ability**: When the ability finishes, `CharacterPanel.HideAbility(ability)` removes the display. If Ctrl is held, hiding is deferred until Ctrl is released.

### The Embedded Roll Dialog (`EmbeddedRollDialog.lua`)

This is the largest and most complex file. `GameHud.CreateEmbeddedRollDialog()` returns a `gui.Panel` with a `.data.ShowDialog(options)` method that drives the entire roll interaction.

#### Key State

- `creature` / `targetCreature` -- the roller and the target of the roll
- `m_multitargets` -- when an ability hits multiple targets, each target gets its own modifier set, boons/banes, surges, and triggers
- `rollProperties` -- a `RollPropertiesPowerTable` (or similar) carrying the power roll tiers and associated damage/effects
- `m_options` -- the full options table passed to `ShowDialog`
- `m_activeModifiers` -- modifiers currently enabled for the roll
- `baseRoll` -- the unmodified roll formula (e.g. `"2d10"`)

#### ShowDialog Options

The `options` table passed to `ShowDialog` includes:

| Field | Description |
|---|---|
| `roll` | Base roll formula string |
| `description` | Display text for the roll (appears in chat) |
| `type` | Roll type string, e.g. `"ability_power_roll"`, `"damage"` |
| `creature` | The creature performing the roll |
| `targetCreature` | Primary target creature |
| `modifiers` | Array of modifier entries (each with `.modifier`, `.hint`, `.override`, etc.) |
| `multitargets` | Array of target info tables (`.token`, `.boons`, `.banes`, `.triggers`, `.modifiers`) |
| `rollProperties` | `RollPropertiesPowerTable` with tier data |
| `symbols` | GoblinScript symbol table for formula evaluation |
| `showDialogDuringRoll` | If true, keep the dialog visible after dice are thrown (for triggers/re-rolls) |
| `amendable` | If true, the roll can be re-rolled |
| `beginRoll` | Callback when dice start rolling |
| `completeRoll` | Callback when roll is accepted and finalized |
| `cancelRoll` | Callback if the user cancels |
| `rollActive` | Callback receiving the active roll object |
| `PopulateCustom` | Function to populate custom result panels (power roll tiers) |
| `PopulateTable` | Function to populate a table panel |
| `autoroll` | If true or a setting key, automatically roll without user input |
| `skipDeterministic` | If true, skip the dialog entirely for deterministic rolls (no dice) |

#### Roll Flow

1. **Prepare**: `ShowDialog` populates the UI, fires `prepare` events on child panels, and calls `CalculateRollText()` to compute the final roll formula with all modifiers applied.

2. **CalculateRollText**: Iterates enabled modifiers, applies boons/banes via `GameSystem.ApplyBoons`, normalizes the roll, and updates `rollInput.text`. Also updates `rollProperties` with modifier effects and fires `textCalculated` for UI refresh.

3. **User interaction**: The user can toggle modifiers (checkboxes), adjust boons/banes, allocate surges, switch between multi-targets, and toggle triggers.

4. **Submit (Roll Dice)**: On submit, `dmhub.Roll{...}` is called with the final roll text, callbacks, and properties. If `showDialogDuringRoll` is true, the dialog transitions to a "rolling" state, then "finishedRolling" when dice land.

5. **Triggers phase**: After rolling, triggered abilities from other creatures can activate. Trigger panels show token icons that can be clicked (by the trigger owner) or pinged (by others). Triggers are synced across clients via `ActiveTrigger` objects dispatched to tokens. A progress dice animation gives players time to use triggers before proceeding.

6. **Complete**: When "Accept Result" is pressed, the `completeFunction` runs: consumes resources for all enabled modifiers, pays trigger costs, applies ongoing effects, handles surge consumption, and calls the `completeRoll` callback.

#### Multi-Target Handling

When an ability targets multiple creatures, `m_multitargets` holds per-target state. The multi-token container shows token portraits that the user can click to switch between targets. Each target has independent:
- Modifiers (some modifiers are target-specific)
- Boons/banes adjustments (`boonsOverride`)
- Surge allocation
- Triggers

`RecalculateMultiTargets()` cycles through all targets, recalculating roll formulas and roll properties for each, then normalizes boons/banes relative to the selected target.

#### Triggers System

Triggers are reactive abilities that other creatures (allies or enemies) can activate in response to a roll. Key mechanics:
- `CreateTriggerPanel(info)` builds UI for each trigger with a token image, label, and augmentation options
- Triggers are dispatched to tokens as `ActiveTrigger` objects so other clients can see and respond to them
- The `think` event on `triggersContainer` periodically syncs trigger state
- `DuplicateTriggerToMultiTargets` propagates "all targets" triggers across the multi-target array
- After-roll triggers (`forceReroll`) can force a re-roll when activated

#### Deterministic Roll Fast Path

If `skipDeterministic` is set and the roll contains no dice (e.g. flat damage), `ShowDialog` bypasses the entire UI: it calls `dmhub.Roll` directly with `silent = true` and `instant = true`, then immediately invokes `completeRoll`.

#### Coroutine Integration

The roll dialog integrates with DMHub's coroutine system. `ShowDialog` can be called from within a coroutine (e.g. the ability cast coroutine). It yields while waiting for the panel to become available or for a previous roll to complete. The `coroutineOwner` field on `resultPanel.data` tracks which coroutine currently owns the dialog.

### Settings

| Setting ID | Description |
|---|---|
| `privaterolls` | Default roll visibility: "visible" (everyone) or "dm" (GM only) |
| `privaterolls:save` | Whether to persist roll visibility preferences |

### Key Functions on `CharacterPanel`

| Function | Description |
|---|---|
| `CharacterPanel.DisplayAbility(token, ability, symbols)` | Shows the ability card in the sidebar. Returns `true` if successful. |
| `CharacterPanel.EmbedDialogInAbility()` | Creates and embeds a roll dialog inside the current ability display. Returns the dialog panel. |
| `CharacterPanel.HideAbility(ability)` | Hides the ability card. Defers if Ctrl is held. |
| `CharacterPanel.HighlightAbilitySection(options)` | Highlights a section of the ability card (`options.section` = `"target"`, `"main"`, or `"effects"`). |

### Hot-Reload Support

Both files include hot-reload guards at the bottom. If `GameHud.instance` already exists when the file is re-executed:
- `AbilitySidebar.lua` re-initializes the ability display panel
- `EmbeddedRollDialog.lua` replaces the roll dialog in the HUD's parent panel
