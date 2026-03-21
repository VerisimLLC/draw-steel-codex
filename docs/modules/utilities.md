# Utilities

The `DMHub Utils/` directory contains 8 shared utility files that load before all other modules. These provide table/string helpers, the GoblinScript formula engine, coroutine utilities, and rendering support used throughout the codebase.

---

## File Overview

| File | Purpose |
|---|---|
| `Utils.lua` | Table and string helper functions, macro registration infrastructure |
| `GoblinScript.lua` | Formula expression evaluator (the "GoblinScript" engine) |
| `CoroutineUtils.lua` | Safe coroutine yield/sleep helpers |
| `MarkdownRenderUtils.lua` | Markdown rendering registry for game types |
| `CompendiumReference.lua` | Cross-references into compendium data tables |
| `SourceReference.lua` | PDF page and source-book references |
| `TableCache.lua` | Cached wrapper around `dmhub.GetTable()` |
| `PrettyPrint.lua` | Debug pretty-printer for Lua tables |

---

## Utils.lua -- Table & String Helpers

`Utils.lua` is the first utility file loaded. It extends the built-in `table` library with functions used everywhere in the codebase:

| Function | Signature | Purpose |
|---|---|---|
| `table.contains` | `(t, element) -> boolean` | Check if a value exists in a table |
| `table.count_elements` | `(t) -> number` | Count entries (works for non-array tables) |
| `table.remove_value` | `(t, element) -> boolean` | Remove all occurrences of a value from an array |
| `table.resize_array` | `(t, size)` | Truncate an array to a given length |
| `table.empty` | `(t) -> boolean` | Check if a table has no entries |
| `table.keys` | `(t) -> table` | Return an array of all keys |
| `table.values` | `(t) -> table` | Return an array of all values |
| `table.set_to_ordered_csv` | `(set, emptyText) -> string` | Convert a set-table to a sorted comma-separated string |

### Macro Registration

Utils.lua also defines the macro registration system via `Commands.RegisterMacro`:

```lua
Commands.RegisterMacro{
    name = "flushcompiledgoblinscript",
    summary = "flush formula cache",
    doc = "Usage: /flushcompiledgoblinscript\n...",
    command = function()
        -- implementation
    end,
}
```

This registers a `/command` that players and the Director can type in chat. The `Commands.GetCurrentArg` function provides tab-completion support by parsing partial command text into structured argument info.

---

## GoblinScript.lua -- The Formula Engine

GoblinScript is the expression language used for damage formulas, ability costs, target filters, prerequisites, and other computed values throughout the game system.

!!! info "Full reference"
    See `GoblinScript_Guide.md` at the repository root for the complete language specification including operators, symbols, and examples.

Key implementation details in `GoblinScript.lua`:

- **Compilation cache** -- Parsed formulas are cached in a module-level table (`g_compiled`). The `/flushcompiledgoblinscript` command clears this cache.
- **Compiled mode toggle** -- A setting (`compiledgoblinscript`, default `true`) controls whether the engine uses compiled evaluation or falls back to interpretation.
- **Debug panel** -- `RegisterGoblinScriptDebugPanel(panel)` hooks a UI panel that receives live debug entries when formulas are evaluated, feeding the GoblinScript Debugger panel in `DMHub Core Panels/`.
- **Error tracking** -- Failed compilations are stored in `g_errors` so the same bad formula does not log repeatedly.

The public API (used by ability definitions, modifiers, etc.):

```lua
-- Compile a formula string
local compiled = GoblinScript.Compile(formula, symbolTable)

-- Evaluate against a context
local result = GoblinScript.Execute(compiled, context)
```

---

## CoroutineUtils.lua -- Async Patterns

A single but important helper for ability resolution and other async workflows:

```lua
function coroutine.safe_sleep_while(predicate)
```

This function yields the current coroutine each frame as long as `predicate()` returns `true`. It includes safety checks:

- Verifies the caller is inside a coroutine (`dmhub.inCoroutine`)
- Verifies the current context allows yielding (`dmhub.canSafelyYield`)
- Logs a warning and returns immediately if either check fails

This is used during ability casts to wait for animations, target selection, and other asynchronous events without blocking the main thread.

---

## Other Utilities

### TableCache.lua

Wraps `dmhub.GetTable()` with a simple cache that is invalidated on `refreshTables` events:

```lua
function GetTableCached(tableName)
    -- returns cached table or fetches and caches it
end
```

All modules can call `GetTableCached("tableName")` instead of `dmhub.GetTable("tableName")` to avoid repeated lookups in the same frame.

### MarkdownRenderUtils.lua

Provides a registry for types and tables that can be rendered as Markdown:

```lua
MarkdownRender.Register({ typeName = "MyType" })
MarkdownRender.RegisterTable({ tableName = "myTable", prefix = "mt" })
```

The `FindTableFromPrefix` and `GetRegisteredPrefixes` functions support Markdown link resolution (e.g., `[mt:some-id]` resolves to an entry in `myTable`).

### CompendiumReference.lua

A `RegisterGameType("CompendiumReference")` that stores a pointer into a compendium data table (`targetTable`, `targetid`, `targetPath`). Used to create cross-references from character sheets and journals into compendium entries for classes, races, subclasses, and similar content.

### SourceReference.lua

A `RegisterGameType("SourceReference")` that stores a reference to a specific page in a PDF source book. Fields: `type` (default `"pdf"`), `docid`, and `page`. Generates URLs via the `url()` method in the format `pdf:docid&page=N`.

### PrettyPrint.lua

Debug utility for printing nested Lua tables in a human-readable format. Useful during development and for the debug log panel.
