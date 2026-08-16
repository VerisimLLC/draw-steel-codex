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
| `UpdateNovelAbilities(charid, abilities)` | Diffs each freshly generated `g_abilities` list against the last snapshot for that creature. See "Novel abilities" below. |
| `NovelContentMarker(extraClass)` | The accent-coloured diamond pip, driven by a `setNovel` event. Used on drawer corners and on ability rows. |

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

**Novel abilities:**

Newly gained abilities (level-up, a kit/item, an ability granted by an effect mid-combat)
announce themselves so the player does not have to go hunting. Every time the root panel's
`refresh` regenerates `g_abilities`, the list is diffed against the last snapshot for that
creature; anything new is "novel".

Three module-local tables drive it, all **in-memory and session-scoped** (cleared on
restart or Lua reload -- deliberately temporary):

| Table | Meaning |
|---|---|
| `g_seenAbilities[charid][key]` | Seen before. Never cleared, so an ability that comes and goes with an effect only announces itself once. |
| `g_novelAbilities[charid][key]` | Novel, unacknowledged -- puts the pip on the corner of the owning drawer (`DrawerTypeForAbility` decides which). |
| `g_ackedNovelAbilities[key]` | Novel, drawer pip already dismissed by opening it -- puts the pip on the ability row. |

Flow: a creature's **first** snapshot in a session is a silent baseline (nothing novel),
otherwise every token you selected at session start would light up every drawer. A
zero-length ability list is never taken as a baseline (a creature mid-load briefly reports
none). Opening a drawer's menu calls `AcknowledgeNovelAbilities`, moving that drawer's
entries from `g_novelAbilities` to `g_ackedNovelAbilities` -- the drawer pip clears and the
rows light up. Closing the menu calls `ClearAcknowledgedNovelAbilities` and they stop being
novel for good. Entries whose ability disappears again before the drawer is ever opened are
pruned, so a badge never points at a menu that no longer lists it.

Ability identity is `guid`, suffixed `:melee` / `:ranged` because melee/ranged bifurcations
are DeepCopies of one parent and share a guid.

Styling lives in `NOVEL_MARKER_RULES`, merged into the action bar root's style cascade
alongside `SEARCH_REVEAL_RULE` so it resolves on ability headings inside an open menu.

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

- Heading boxes above the group holding the trigger's name and its prompt -- only for a multi-mode trigger (`ActiveTrigger:UsesModeHeading()`). Such a trigger draws one card per mode, so its own name and prompt would otherwise displace the first mode's; with the headings present every card carries its own mode's name and rules. Mode 1 lives on the trigger as `activateText` / `activateRules` rather than in `modes`.
- `!` icon (gold = normal, blue = free)
- Title and markdown rules text
- Target token images (with optional retarget arrow)
- Cost diamond (if heroic-resource cost required). A mode-driven trigger's option cards carry no cost of their own -- picking any mode costs the trigger's cost -- so they repeat the trigger's diamond. A `powerRollModifier` trigger's options are extra resource spends and price themselves.
- Buttons: Activate, Enhancement Options, Dismiss
- "Dismiss Triggers" bar to dismiss all at once

A mode whose `condition` is not met is hidden, unless the author filled in its **Condition Reason** (`modeList[i].conditionReason`, edited under Mode Condition in the ability editor's Modes section). With a reason set, the mode is offered anyway: the card is dimmed via the `unavailableMode` class and carries the reason in `triggerUnavailableNote`, but stays pressable so the table can allow it. Blank -- the default -- keeps the original hide behaviour.

Because hidden modes leave holes in `modes`, an option's position there is **not** its position in `modeList`. Each entry records `modeIndex`, and `ActiveTrigger:ModeIndexForTriggered` resolves it; `symbols.mode` (which selects behaviors via their `modesSelected`) must go through that helper rather than the old `trigger.triggered + 1`, or every mode after a hidden one runs the wrong entry's behaviors. Prompts serialized before `modeIndex` existed fall back to the positional reading.

Trigger activation either fires immediately or enters target-selection mode (via `chooseTarget` event on the ability controller) if the trigger supports retargeting.

## Integration

- The action bar is registered with `RegisterCustomActionBar(CreateActionBar)` at file end.
- Trigger panel coordinates with the ability controller for target selection and with the action menu for show/hide toggling.
- Visual map feedback (radius markers, shapes, line-of-sight rays) is managed through `dmhub.CalculateShape`, `g_token:MarkMovementRadius`, and `dmhub.MarkLineOfSight`.
- Abilities are cast via `ability:Cast(targets, symbols, costs)` after cost/target validation.
