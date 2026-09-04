# GoblinScript

GoblinScript is a **pure functional expression language** used throughout Draw Steel Codex for game formulas. It powers ability damage, costs, prerequisites, modifier conditions, and display text.

## What it looks like

GoblinScript formulas are strings that evaluate to numbers, booleans, or text:

```
Self.Might + 2
2d6 + Self.Level
Self has Condition 'Bleeding'
Self.Stamina < Self.Stamina Max / 2
```

## Where it's used

- **Ability costs** — Dynamic action costs based on caster state
- **Damage formulas** — `2d6 + Self.Might` with power roll tier scaling
- **Prerequisites** — `Self.Level >= 3`
- **Target filters** — `Target is Enemy and Target is not Dead`
- **Modifier activation** — `Self has Condition 'Dazed'`
- **Display text** — Dynamic labels showing calculated values

## How it works in code

The core function is `ExecuteGoblinScript`:

```lua
function ExecuteGoblinScript(formula, symbols, defaultValue, contextMessage)
    if formula == "" or formula == nil then
        return defaultValue
    end
    local fn = g_compiled[formula]
    if fn == nil then
        local out = {}
        fn = dmhub.CompileGoblinScriptDeterministic(formula, out)
        g_compiled[formula] = fn
    end
    if fn == false then
        return defaultValue
    else
        local ok, result = pcall(fn, symbols)
        return result
    end
end
```

*Source: `DMHub_Utils_5b73/GoblinScript.lua`*

Formulas are **compiled once and cached** for performance. The `symbols` table provides the context (who is "Self", who is "Target", etc.).

## Real usage: dynamic ability cost

```lua
function ActivatedAbility:GetNumberOfActionsCost(caster, symbols)
    if type(self.actionNumber) == "number" then
        return self.actionNumber
    end
    -- actionNumber is a GoblinScript formula string
    local result = ExecuteGoblinScript(
        self.actionNumber,
        caster:LookupSymbol(symbols or {mode = 1}),
        1
    )
    return result
end
```

*Source: `DMHub_Game_Rules_fc51/ActivatedAbility.lua`*

When `actionNumber` is a string (like `"1 + Self.ExtraActions"`), it's evaluated as GoblinScript. When it's a plain number, it's returned directly.

## Key symbols

| Symbol | Meaning |
|--------|---------|
| `Self` | The creature being evaluated |
| `Caster` | The creature using an ability |
| `Target` | The target of an ability |
| `Cast` | The current cast context |
| `Ability` | The ability being used |

## Language features

- **Case-insensitive** — `Self.Might` and `self.might` are the same
- **Space-insensitive** in multi-word names — `Stamina Max` and `StaminaMax` both work
- **Dice notation** — `2d6`, `4d8 keep 3`, `1d20 reroll 1`
- **Operators** — `+`, `-`, `*`, `/`, `=`, `!=`, `<`, `>`, `<=`, `>=`, `and`, `or`, `not`
- **Text operators** — `is`, `has`, `contains`
- **Built-in functions** — `min()`, `max()`, `floor()`, `ceiling()`
- **No side effects** — GoblinScript is pure; it only reads state, never writes it

## Further reading

The complete GoblinScript reference — including all symbols, operator precedence, dice modifiers, and worked examples — is in [GoblinScript_Guide.md](https://github.com/VerisimLLC/draw-steel-codex/blob/main/GoblinScript_Guide.md) in the repo root.

## Key points

- GoblinScript is a **formula language**, not a general-purpose language
- Formulas are **strings** stored on game objects and **evaluated at runtime**
- The engine **compiles and caches** formulas for performance
- **Symbols** (`Self`, `Target`, etc.) provide evaluation context
- The language is **case-insensitive** and **space-insensitive**
- It supports **dice notation** natively
- It has **no side effects** — read-only evaluation
