# DrawSteelActionBar

The action bar is the main UI bar at the bottom of the screen that appears when a creature token is selected. It lets players (and the DM) browse, select, and cast abilities -- handling resource costs, targeting, and visual feedback on the map.

## Files

### DrawSteelActionBar.lua (~4700 lines)

The core action bar implementation. Registered at the bottom of the file via `RegisterCustomActionBar(CreateActionBar)`.

**Major components:**

| Function / Section | Purpose |
|---|---|
| `ActionBarDrawer(args)` | Creates one "drawer" cell in the bar (action, maneuver, trigger, move, malice, free). Each drawer shows resource availability, an icon of the last-used ability, and a movement-speed bar or malice-cost diamond where appropriate. |
| `CreateActionBar()` | Top-level factory. Assembles the drawer strip, the action menu, the ability controller, and the trigger-reaction panel into a single root panel. |
| `ActionMenu()` | Dropdown that appears above a drawer when clicked. Lists available abilities grouped by categorization (Skill, Heroic, Villain Action, Malice, etc.). |
| `AbilityHeading(args)` | Clickable ability button inside the action menu. Left-click selects for casting; right-click opens a context menu (Share to Chat, View Source, Edit). |
| `ActionSubMenu(args)` | Groups abilities by category inside the action menu. |
| `CreateAbilityController()` | The targeting/casting overlay. Manages confirm/skip buttons, mode selection, forced-movement-type selection, channeled-resource slider, altitude control, shift toggle, synthesized-spell picker, and token-selection list. |
| `CalculateSpellTargeting(forceCast, initialSetup)` | Core casting logic. Builds the target list, validates range/line-of-sight, updates radius and shape markers on the map, and -- when ready -- calls `ability:Cast()`. |
| `CreateTargetInfo(ability)` | Builds a target-info structure for token-targeting abilities. |
| `CreateShiftController()` | Radio toggle: Shifting vs Not Shifting. |
| `CreateAltitudeController()` | Alt+scroll-wheel UI for adjusting target altitude. |
| `CreateSynthesizedSpellsPanel()` | Picker for synthesized spell variations. |
| `CreateTokenSelectionContainer()` | UI for selecting individual token targets. |
| `TriggerPreviewPanel()` | Preview of a triggered ability before activation. |
| `CreateTriggerReactionPanel()` | Progress/reaction panel at bottom-center of the screen. |

**Key global state:**

| Variable | Type | Role |
|---|---|---|
| `g_currentAbility` | `ActivatedAbility?` | Ability currently being cast |
| `g_token` / `g_creature` | `CharacterToken?` / `Creature?` | Caster token and its properties |
| `g_abilities` | `ActivatedAbility[]` | All abilities available to the selected token |
| `g_targetsChosen` | `string[]` | Charids of selected targets |
| `g_pointTargeting` | table | Tracks shapes, radius markers, labels for AoE/line/cone targeting |
| `g_pointForceTargets` | `table<string,CharacterToken>` | Tokens forced into a targeting radius |
| `g_currentSymbols` | table | Symbol table passed to GoblinScript (mode, charges, range, forced movement, invoker, etc.) |
| `g_currentCostProposal` | `CostProposal?` | Proposed resource expenditure for current cast |
| `g_resources` | `table<string,number>` | Current character resource levels |
| `g_casterTokenStack` | stack | Supports nested casting (push/pop caster overrides) |

**Settings:**

- `newactionbar` (bool, default true) -- "Use New Action Bar" preference toggle.
- `preferredforcedmovementtype` (string, default "none") -- Remembers the user's last forced-movement choice.

**Supported target types:** `self`, `target`, `all`, `point`, `emptyspace`, `anyspace`, `line`, `cone`, `areatemplate`, `map`.

### DrawSteelTriggerPanel.lua

Creates the floating trigger panel that appears above the trigger drawer when the selected token has available triggered abilities (reactions).

**Exports via `mod.shared`:**

| Export | Purpose |
|---|---|
| `triggerGradient` | Radial gradient for standard trigger backgrounds |
| `freeTriggerGradient` | Radial gradient for free-trigger backgrounds |
| `CreateTriggerPanel()` | Factory returning the trigger panel |

**Panel structure per trigger:**

- `!` icon (gold = normal, blue = free)
- Title and markdown rules text
- Target token images (with optional retarget arrow)
- Cost diamond (if heroic-resource cost required)
- Buttons: Activate, Enhancement Options, Dismiss
- "Dismiss Triggers" bar to dismiss all at once

Trigger activation either fires immediately or enters target-selection mode (via `chooseTarget` event on the ability controller) if the trigger supports retargeting.

## Integration

- The action bar is registered with `RegisterCustomActionBar(CreateActionBar)` at file end.
- Trigger panel coordinates with the ability controller for target selection and with the action menu for show/hide toggling.
- Visual map feedback (radius markers, shapes, line-of-sight rays) is managed through `dmhub.CalculateShape`, `g_token:MarkMovementRadius`, and `dmhub.MarkLineOfSight`.
- Abilities are cast via `ability:Cast(targets, symbols, costs)` after cost/target validation.
