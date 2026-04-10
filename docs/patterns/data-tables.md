# Data Tables

Data Tables are the persistence layer for game content — abilities, conditions, classes, resources, monsters, and everything in the compendium. They store the *definitions* of game objects (as opposed to [Shared Documents](shared-documents.md), which store live session state).

## Reading a table

Use `dmhub.GetTable(tableName)` to get a table by name:

```lua
local resourcesTable = dmhub.GetTable(CharacterResource.tableName)
```

The returned value is a table keyed by unique IDs (GUIDs). Each value is a Game Type instance.

## Iterating entries

Always use `unhidden_pairs()` instead of `pairs()`:

```lua
local resourcesTable = dmhub.GetTable(CharacterResource.tableName)
for k, v in unhidden_pairs(resourcesTable) do
    if v.name == "Recovery" then
        recoveryid = k
        recoveryInfo = v
    end
end
```

*Source: `Draw_Steel_Ability_Behaviors_aef5/AbilityRecoverSelection.lua`*

!!! info "Why `unhidden_pairs`?"
    DMHub uses "soft deletion" — entries aren't removed, they're marked hidden. `unhidden_pairs()` automatically skips these soft-deleted entries. Using raw `pairs()` would include deleted items.

## Building dropdowns from table data

A common pattern is building UI dropdown options from a table:

```lua
function CharacterResource.GetDropdownOptions(grouping, includeNone)
    local result = {}
    local resourceTable = dmhub.GetTable("characterResources") or {}
    for k, resource in pairs(resourceTable) do
        if (not resource:try_get("hidden", false))
           and (grouping == nil or resource.grouping == grouping) then
            result[#result+1] = {id = k, text = resource.name}
        end
    end
    return result
end
```

*Source: `DMHub_Game_Rules_fc51/Resource.lua`*

## Writing to a table

Use `dmhub.SetAndUploadObject(tableName, id, obj)` to write an entry:

```lua
dmhub.SetAndUploadObject("charConditions", conditionId, conditionObj)
```

This serializes the object, writes it locally, and uploads it to the cloud.

## Common table names

| Table Name | Contains | Defined In |
|-----------|---------|-----------|
| `"characterResources"` | Resources (Recovery, Surges, etc.) | `Resource.lua` |
| `"charConditions"` | Conditions (Bleeding, Dazed, etc.) | `Condition.lua` |
| `"kits"` | Kit definitions | `MCDMKit.lua` |
| `"activatedAbilities"` | Ability definitions | `ActivatedAbility.lua` |

Table names are typically stored as a `tableName` field on the Game Type (e.g., `Kit.tableName = "kits"`).

## Key points

- **Read** with `dmhub.GetTable(name)` — returns a GUID-keyed table
- **Iterate** with `unhidden_pairs()` — never use raw `pairs()` on data tables
- **Write** with `dmhub.SetAndUploadObject(table, id, obj)` — handles serialization and cloud sync
- **Table names** are strings, typically stored on the Game Type as `.tableName`
- Data tables store **definitions** (content), not **session state** (use [Shared Documents](shared-documents.md) for that)
