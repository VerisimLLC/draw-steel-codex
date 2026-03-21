# Token Mutations

When you need to change a token's properties outside of the character sheet, you **must** wrap mutations in `token:ModifyProperties{}`. This is one of the most important patterns in the codebase.

## Why it matters

`ModifyProperties` does three things:

1. **Diffs** — Only the changed fields are uploaded, not the entire token
2. **Cloud sync** — Changes are sent to all connected clients
3. **Undo support** — Changes can be reverted via the undo stack

Without it, changes would be lost, invisible to other players, or break undo.

## Basic usage

```lua
token:ModifyProperties{
    description = "Reset Hero Tokens",
    execute = function()
        token.properties:SetHeroTokens(n, "Session Reset")
    end,
}
```

*Source: `Draw_Steel_Core_Rules_1b8f/MCDMCharacterPanel.lua`*

The `description` string appears in the undo history, so make it human-readable.

## More examples

Consuming surges:

```lua
token:ModifyProperties{
    description = "Change Surges",
    execute = function()
        token.properties:ConsumeSurges(-diff, "Manually Set")
    end,
}
```

*Source: `Draw_Steel_Core_Rules_1b8f/MCDMCharacterPanel.lua`*

Shared recovery consumption (with dynamic description):

```lua
token:ModifyProperties{
    description = string.format("Shared recovery used by %s", mytoken.name),
    execute = function()
        token.properties:ConsumeResource(
            CharacterResource.recoveryResourceId,
            refreshType, using,
            string.format("Shared recovery used by %s", mytoken.name)
        )
    end,
}
```

*Source: `DMHub_Game_Rules_fc51/Resource.lua`*

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `execute` | function | *required* | Function that mutates `token.properties` |
| `description` | string | `""` | Human-readable label for the undo stack |
| `undoable` | boolean | `true` | Set `false` for non-undoable changes |
| `combine` | boolean | `false` | If `true`, combines with other uploads this frame as a transaction |

## The character sheet exception

!!! note "Exception: Character sheet code"
    Code running inside the character sheet or character builder modifies `token.properties` **directly** without `ModifyProperties`. The sheet manages its own upload lifecycle. If you're editing code in `CharacterSheet` or `CharacterBuilder` files, you don't need this wrapper.

## Deprecated alternative

`BeginChanges`/`CompleteChanges` is the old API. Always use `ModifyProperties` instead — it's safer and supports undo.

## Key points

- **Always wrap** property mutations in `ModifyProperties` (outside the character sheet)
- **Include a description** — it shows up in undo history
- **Keep `execute` focused** — do the mutation and nothing else
- The character sheet is the only exception to this rule
