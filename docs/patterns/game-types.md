# Game Types

Game Types are the foundation of the DMHub data model. Every persistent game object — creatures, abilities, conditions, equipment, kits — is a registered Game Type.

## Registering a type

Use `RegisterGameType` to create a new type:

```lua
CharacterAttribute = RegisterGameType("CharacterAttribute")
CharacterAttribute.baseValue = 10

function CharacterAttribute:Value()
    return math.tointeger(self.baseValue)
end

function CharacterAttribute:Modifier()
    local n = CharacterAttribute.Value(self)
    return GameSystem.CalculateAttributeModifier(self, n)
end
```

*Source: `DMHub_Game_Rules_fc51/Creature.lua`*

This does three things:

1. Creates a global `CharacterAttribute` table
2. Registers it with the engine's serialization system (so instances can be saved/loaded)
3. Lets you declare fields (`baseValue = 10`) and methods (`:Value()`, `:Modifier()`)

## Inheritance

Pass a parent type name as the second argument:

```lua
CharacterCondition = RegisterGameType("CharacterCondition", "CharacterFeature")
CharacterCondition.name = "New Condition"
CharacterCondition.tableName = "charConditions"
```

The child type inherits all fields and methods from the parent. You can override them by redeclaring.

## Extending a type from another file

A common pattern in the Draw Steel layer is extending a foundation type. Save the base method, then wrap it:

```lua
-- In Draw_Steel_Core_Rules_1b8f/MCDMCreature.lua
local g_baseInvalidate = creature.Invalidate
function creature:Invalidate()
    g_baseInvalidate(self)
    if mod.unloaded then
        return
    end
    self._tmp_calculatedAttributes = nil
    self._tmp_adjacentLocs = nil
    self._tmp_flankfromanydirection = nil
end
```

*Source: `Draw_Steel_Core_Rules_1b8f/MCDMCreature.lua`*

This pattern:

1. Saves a reference to the base `Invalidate` method
2. Replaces it with a new function that calls the base first
3. Adds Draw Steel-specific cleanup afterward

You'll see `local g_base...` throughout the Draw Steel layer.

## Transient fields

Fields prefixed with `_tmp_` are **transient** — the engine skips them during serialization. Use them for ephemeral runtime state:

```lua
self._tmp_calculatedAttributes = nil
```

!!! warning "Safe access required"
    Reading a `_tmp_` field that was never set will throw an error. Always use `obj:try_get("_tmp_foo")` for safe access, or check with `obj:has("_tmp_foo")`.

## Complex example: Kit registration

A more complete example showing field declarations, enums, and registration helpers:

```lua
Kit = RegisterGameType("Kit")
Kit.tableName = "kits"
Kit.kitTypes = {}

Kit.RegisterKitType{
    id = "martial",
    text = "Martial",
    keywords = {"Weapon"},
    displayOrd = 1,
    lockedByDefault = true,
}
```

*Source: `Draw_Steel_Core_Rules_1b8f/MCDMKit.lua`*

## Key points

- **All persistent game objects** must be registered Game Types
- **Fields are declared** by setting them on the type table (e.g., `Kit.tableName = "kits"`)
- **Methods are declared** with the colon syntax (e.g., `function Kit:GetType()`)
- **Extending types** from other files uses the `local g_base = Type.Method` pattern
- **Transient fields** use the `_tmp_` prefix and require `try_get()` for safe access
- **Inheritance** is declared via the second argument to `RegisterGameType`
