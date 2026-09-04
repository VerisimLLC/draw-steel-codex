# Keywords Reference

Keywords are string tags attached to abilities, items, and monsters. They drive filtering, targeting rules, modifier applicability, and UI display throughout the codex.

## Data Structure

Keywords are stored as simple `table<string, boolean>` maps where keys are keyword names and values are `true`:

```lua
ability.keywords = {
    Strike = true,
    Melee = true,
    Weapon = true,
}
```

## Registration

The game system maintains two registries of valid keywords, populated at startup in `Draw Steel Core Rules/MCDMRules.lua`:

```lua
GameSystem.RegisterAbilityKeyword("Strike")   -- adds to GameSystem.abilityKeywords
GameSystem.RegisterItemKeyword("Potion")       -- adds to GameSystem.itemKeywords
```

Both registries are `table<string, boolean>` maps stored on the `GameSystem` global. `GameSystem.hasAbilityKeywords` is set to `true` once any ability keyword is registered, which gates keyword-related UI.

**Registered ability keywords:** Animal, Area, Strike, Focus, Kit, Magic, Melee, Psionic, Weapon, Ranged, Telepathy, Air, Earth, Fire, Green, Rot, Void, Water, Routine, Performance, Beastheart, Companion, Charge, Telekinesis, Chronopathy.

**Registered item keywords:** Potion, Neck, Light/Medium/Heavy Armor, Oil, Scroll, Arms, Hands, Head, Feet, Waist, Shield, Implement, Wand, Whip, Light/Medium/Heavy Weapon, Polearm, Net, Bow, Ring.

Registration lives in `DMHub Game Rules/GameSystem.lua:159-166`.

## Keyword Aliases (Remappings)

Keywords can be renamed across versions while keeping old data and old code working. This is handled by `ActivatedAbility.KeywordRemappings` in `Draw Steel Core Rules/MCDMActivatedAbility.lua:215-217`:

```lua
ActivatedAbility.KeywordRemappings = {
    Attack = "Strike",
}
```

This table maps old keyword names to their canonical replacements. The alias system is enforced at four points:

### 1. Deserialization (migration)

When an ability is loaded from storage, `OnDeserialize` migrates old keywords to canonical names (`MCDMActivatedAbility.lua:224-229`):

```lua
for k, v in pairs(ActivatedAbility.KeywordRemappings) do
    if self.keywords[k] then
        self.keywords[v] = true   -- add canonical name
        self.keywords[k] = nil    -- remove old name
    end
end
```

This means saved data is migrated in place -- abilities stored with `Attack = true` become `Strike = true` on load.

### 2. HasKeyword (lookup)

Queries remap before checking (`MCDMActivatedAbility.lua:238-240`):

```lua
function ActivatedAbility:HasKeyword(keyword)
    keyword = ActivatedAbility.KeywordRemappings[keyword] or keyword
    return self.keywords[keyword] == true
end
```

So `ability:HasKeyword("Attack")` transparently checks for `"Strike"`.

### 3. AddKeyword / RemoveKeyword (mutation)

Both methods remap before modifying the table (`MCDMActivatedAbility.lua:232-247`):

```lua
function ActivatedAbility:AddKeyword(keyword)
    keyword = ActivatedAbility.KeywordRemappings[keyword] or keyword
    self.keywords = DeepCopy(self.keywords)
    self.keywords[keyword] = true
end

function ActivatedAbility:RemoveKeyword(keyword)
    self.keywords = DeepCopy(self.keywords)
    keyword = ActivatedAbility.KeywordRemappings[keyword] or keyword
    self.keywords[keyword] = nil
end
```

Note that the Draw Steel versions `DeepCopy` the keywords table before mutating. This is because keyword tables may be shared across cloned/template objects, and mutation must not affect other instances.

### 4. Display (CanonicalKeyword)

All UI code that displays keyword names to users calls `ActivatedAbility.CanonicalKeyword(keyword)` to map any stale alias to its canonical name before rendering:

```lua
function ActivatedAbility.CanonicalKeyword(keyword)
    return ActivatedAbility.KeywordRemappings[keyword] or keyword
end
```

This is used everywhere keywords are shown: ability cards, action bar, character sheet, monster stat blocks, damage reduction/immunity text, keyword picker widgets, modifier editors, and error messages. The helper is also available via `table.mapped_keys(keywordsTable, ActivatedAbility.CanonicalKeyword)` for bulk conversion.

### Base vs. Draw Steel Methods

The base `ActivatedAbility` class in `DMHub Game Rules/ActivatedAbility.lua:283-303` defines simple keyword methods without remapping. The Draw Steel layer in `MCDMActivatedAbility.lua` **overrides** these methods to add alias support. The base versions are:

```lua
function ActivatedAbility:AddKeyword(keyword)
    if self.keywords == ActivatedAbility.keywords then
        self.keywords = {}
    end
    self.keywords[keyword] = true
end

function ActivatedAbility:HasKeyword(keyword)
    return self.keywords[keyword] == true
end

function ActivatedAbility:RemoveKeyword(keyword)
    self.keywords[keyword] = nil
end
```

## Where Keywords Are Used

### On Abilities

Every `ActivatedAbility` has a `.keywords` table. Keywords are used for:

- **Targeting rules**: Strike-keyword abilities cannot target hidden creatures (`DrawSteelActionBar.lua`)
- **Modifier filtering**: Modifiers can specify keyword filters to only apply to abilities with certain keywords (e.g. `ModifierModifyAbilities.lua`)
- **Signature ability events**: The system fires events when Strike or Area abilities are used (`MCDMRules.lua`)
- **Monster AI**: AI checks for Melee, Ranged, Strike, Charge keywords to determine ability usage (`Monster AI/MonsterAI.lua`)
- **Trigger conditions**: Power roll triggers can filter by keyword (`PowerTableTriggers.lua`)
- **Action bar search**: The action bar UI supports filtering abilities by keyword text

### On Monsters

Monsters have a `.keywords` table (`MCDMMonster.lua:18`) used for descriptive/organizational purposes. Accessed via `monster:Keywords()`.

### On Items/Equipment

Items use keywords for categorization (armor weight, weapon type, slot). The item editor uses `GameSystem.KeywordsSetToDropdownList()` to build dropdown options combining both ability and item keyword registries.

## GoblinScript Integration

Keywords are exposed to GoblinScript formulas via a registered symbol (`MCDMActivatedAbility.lua:249-264`):

```lua
RegisterGoblinScriptSymbol(ActivatedAbility, {
    name = "Keywords",
    type = "set",
    calculate = function(c)
        local strings = {}
        for k, v in pairs(c.keywords) do
            strings[#strings + 1] = string.lower(k)
        end
        return StringSet.new { strings = strings }
    end,
})
```

This allows formulas like `Ability.Keywords has 'Ranged'` or `Ability.Keywords has 'Attack'` (note: GoblinScript queries use the raw keyword strings, so alias remapping does not apply here -- both `'attack'` and `'strike'` will work since the set contains lowercase versions of whatever is actually stored).

## Keyword Picker UI

`Draw Steel UI/DSKeywordPicker.lua` provides `gui.KeywordSelector(args)`, a reusable widget for editing keywords. It:

1. Displays currently selected keywords with delete buttons
2. Shows a searchable dropdown of available keywords (from `GameSystem.abilityKeywords`), excluding already-selected ones
3. Fires a `change` event when keywords are added or removed

Usage:
```lua
gui.KeywordSelector{
    keywords = ability.keywords,  -- reference to the keywords table
    change = function(element)
        -- keywords table has been mutated
    end,
}
```

## Helper: KeywordsSetToDropdownList

`GameSystem.KeywordsSetToDropdownList(keywords, set)` in `GameSystem.lua:168-185` converts a keywords registry table into a sorted list of `{id, text}` entries suitable for dropdown menus. It handles nested tables (recursive flattening) and sorts alphabetically.

## Key Files

| File | What it does |
|------|-------------|
| `DMHub Game Rules/GameSystem.lua:152-185` | Registration functions and dropdown helper |
| `DMHub Game Rules/ActivatedAbility.lua:283-303` | Base keyword methods (no aliases) |
| `Draw Steel Core Rules/MCDMActivatedAbility.lua:215-264` | Alias remappings, overridden methods, GoblinScript symbol |
| `Draw Steel Core Rules/MCDMRules.lua:2278-2327` | Keyword registration calls |
| `Draw Steel Core Rules/MCDMMonster.lua:18-22` | Monster keyword storage |
| `Draw Steel UI/DSKeywordPicker.lua` | Keyword selector UI widget |
