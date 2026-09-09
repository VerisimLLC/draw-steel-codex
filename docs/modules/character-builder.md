# Character Builder

The `Draw Steel Character Builder/` directory implements the **character creation wizard** -- a step-by-step UI that walks players through building a Draw Steel hero. It contains **24 Lua files** organized around an MVC architecture with a centralized state machine.

## Architecture overview

The builder follows a **Model-View-Controller** pattern:

```
MainPanel.lua          Controller -- handles refreshToken, fires refreshBuilderState
    |
State.lua              Model -- key-value state object passed to all children
    |
Selectors.lua          Navigation -- step buttons (Ancestry, Culture, Career, ...)
    |
FeatureSelector.lua    View -- reusable selection list UI
*Detail.lua files      View -- per-step detail panels
```

!!! info "Lazy loading"
    Large UI panels are created only when first needed. This keeps the builder responsive even though it has many possible screens.

## The state machine

The builder tracks which step the player is on using `CharacterBuilder.SELECTOR`:

```lua
CharacterBuilder.SELECTOR = {
    BACK        = "back",
    CHARACTER   = "character",
    ANCESTRY    = "ancestry",
    CULTURE     = "culture",
    CAREER      = "career",
    CLASS       = "class",
    KIT         = "kit",
    COMPLICATION = "complication",
    TITLE       = "title",
}
CharacterBuilder.INITIAL_SELECTOR = CharacterBuilder.SELECTOR.ANCESTRY
```

The player progresses through these steps in order, starting with Ancestry. Each step has a corresponding detail panel and selection UI.

## Event flow

State changes propagate through the builder via a custom event system:

1. A token property changes (e.g., player picks an ancestry)
2. `MainPanel.lua` handles the `refreshToken` event
3. It fires `refreshBuilderState` on the entire UI tree, passing the `State` object
4. Each panel reads from `State` to decide what to display

The `State` object uses dot-separated keys for namespacing:

```
state:Get("ancestry.selectedId")   -- GUID of chosen ancestry
state:Get("token")                 -- the CharacterToken being edited
```

## Helper functions

`CharacterBuilder.lua` defines helpers used across all builder files:

| Function | Purpose |
|----------|---------|
| `_fireControllerEvent(eventName, ...)` | Fires an event on the main controller panel |
| `_getHero()` | Returns the creature from the token, validated as a hero via `:IsHero()` |
| `_getToken()` | Returns the `CharacterToken` from the current state |

## Files by purpose

### Core framework

| File | Description |
|------|-------------|
| `CharacterBuilder.lua` | Type registration, constants, selector enum, helper functions |
| `MainPanel.lua` | Controller panel -- handles `refreshToken`, dispatches `refreshBuilderState` |
| `State.lua` | State object implementation (key-value store carried through the tree) |
| `Selectors.lua` | Left-column navigation buttons for each builder step |
| `FeatureSelector.lua` | Reusable list selection UI (filters when options >= 20) |
| `Styles.lua` | Shared style constants for builder panels |
| `FeatureCache.lua` | Caches feature lookups to avoid redundant table scans |

### Step detail panels

Each builder step has a detail panel that shows information about the selected option:

| File | Builder step |
|------|-------------|
| `AncestryDetail.lua` | Ancestry selection and trait display |
| `CultureDetail.lua` | Culture selection and aspect bonuses |
| `CareerDetail.lua` | Career (background) selection |
| `ClassDetail.lua` | Class selection and subclass preview |
| `KitDetail.lua` | Kit selection (equipment + ability packages) |
| `ComplicationDetail.lua` | Complication selection |
| `TitleDetail.lua` | Title selection |
| `DescriptionDetail.lua` | Character name, appearance, personality |

### Choice and status panels

| File | Description |
|------|-------------|
| `CharacterPanel.lua` | Summary view of the character being built |
| `CharacterAttributeChoice.lua` | Characteristic score assignment UI |
| `CharacterCultureChoice.lua` | Culture aspect selection sub-choices |
| `CharacterKitChoice.lua` | Kit sub-option selection |
| `CharacterIncidentChoice.lua` | Inciting incident selection |
| `CharComplicationChoice.lua` | Complication sub-choice handling |
| `CharacterTitleChoice.lua` | Title sub-choice handling |
| `SelectionStatus.lua` | Status indicators showing completion per step |
| `DescriptionStatus.lua` | Status for the description/flavor step |
