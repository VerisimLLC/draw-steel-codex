# Block editor: coding plan and infrastructure fit check

Date: 2026-11-24. Status: **historical** (2026-11-26). Kept for its infrastructure research.
Where it differs from the decision ledger in [`BLOCK_EDITOR_FRAMEWORK.md`](BLOCK_EDITOR_FRAMEWORK.md)
(authoritative) or the current [`BLOCK_EDITOR_IMPLEMENTATION_PLAN.md`](BLOCK_EDITOR_IMPLEMENTATION_PLAN.md),
those win. Known differences: registries live on `Block` in `DMHub Utils/Block.lua`, declared
beside the types (not `BlockEditor.Register*`); block colours are fixed hex with a glyph, not theme
tokens; subclasses are never "linked" from other classes; undo is the editor's own (plan section 12);
rollout and phasing are being settled with the owner. No Lua or engine file was changed.

This reviews the decided design in `BLOCK_EDITOR_FRAMEWORK.md` (D1-D10, Q1-Q3) and
`ui-mockup/block-copy/REGISTRY_EXAMPLES.md` against the real codex code, and turns it into a
build plan. The owner's rule being tested: **control sits where a type is registered, never in
editor UI code.**

Every claim about existing code has a `file:line` reference. Line numbers are from the working
tree on the date above.

## 1. Verdict in one page

The design holds, and it needs **no engine (C#) change**. It does need six small changes to
existing Lua, and five corrections to the decided design. None of them is large.

**Design assumptions that do not hold against the code:**

| # | Assumption in the brief | What the code does | Fix |
|---|---|---|---|
| A1 | `CharacterModifier.RegisterType` gains a third argument that is "merged into `TypeInfo[id]`" | All 62 types call `RegisterType(id, text)` first and then **assign a whole new table** to `CharacterModifier.TypeInfo.<id>`. Example: `power` registers at `MCDModifyPowerRolls.lua:179` and assigns at `:481`; `attribute` at `CharacterModifier.lua:557` and `:573`. A merge done by `RegisterType` is wiped by that assignment. | Put `block` / `blocks` **inside the TypeInfo table literal**. `TypeInfo` is already an open table (`CharacterModifier.lua:433`). `RegisterType` then needs no change at all. |
| A2 | `CharacterChoice.RegisterChoice` is a registry hosts can read | It is defined in a UI file and stores into a **file-local** table with no accessor (`Draw Steel UI/DSClassEditor.lua:3-7`). Only that file reads it (`:1062`, `:1109`). The seven built-in choices are not registered: they are hard-coded in the dropdown (`:1035-1059`, `:1080-1094`) and in an if/elseif chain (`:1109-1146`). | Move the registry to the rules layer with a public accessor, and register the built-ins (section 7, change C2). |
| A3 | Q2: "the first block whose `match` accepts opens the record" | One `power` record can hold `modtype`, `damageModifier`, `potencymod` and `surges` at once (`MCDModifyPowerRolls.lua:906`, `:1014`, `:1375-1385`). First-match would open it as "Edge" and push the damage, potency and surges into "Advanced editor (3)". The prototype's Combine feature depends on the opposite. | Replace first-match with **claims**: every block of the type says which fields it claims. One claimant = a plain block. Several = a combined block (section 4.8). |
| A4 | The `write` sketch for roll options (brief section 4a) | Two bugs. (1) `(v.selected == "never" and false) or "1"` always yields `"1"`, so "never" saves as "always". (2) "Always" is stored as boolean `true` (`MCDModifyPowerRolls.lua:721`, `:1921`), not `"1"`; and the read sketch reads `rec.activationCondition` directly, which **raises** on imported records that lack the field (`:636-639`; only `displayCondition` has a class default, `:10`). | Write `true` / `false` / the formula. Read with `rec:try_get(...)`. Never call `write` for a slot the author did not touch (section 4.5). |
| A5 | A host stack is one field: `stacks = { { field = "modifierInfo", ... } }` | `modifierInfo` is a `ClassLevel` (`Feat.lua:87-91`). Its `.features` holds features and choices; **modifiers live one level down** in `feature.modifiers` (`CharacterFeature.lua:572-573`). Choices are siblings of the feature, not children. | The framework needs an explicit **feature layer** between host and blocks (section 5.2). |

**Fit summary:**

| Piece | Rating |
|---|---|
| Ability behaviour registration keeps `block` | Fits as-is (typing line needed) |
| Modifier registration keeps `block` | Fits as-is, if declared in TypeInfo (A1) |
| Choice registration | Needs a small additive change (A2) |
| Slot-to-field mapping, read-back, unclaimed fields | Fits as-is |
| Prose from sentence, formula to English | Fits as-is (`GoblinScriptProse.Render`) |
| Formula slot docs | Fits as-is, with the real `examples` shape |
| Logic wrapper | Fits, with one declared rule per type (filter support) |
| Combine roll changes | Fits, once Q2 is corrected (A3) |
| Hosts | Needs the feature layer (A5) |
| Drag and drop | Fits as-is (engine has `draggable` / `dragTarget` / `canDragOnto`) |
| Performance | Fits, only with lazy build and in-place refresh |
| Undo, conflict detection | Framework must own undo; conflict detection is unverified |

## 2. What the registrations do today (quoted)

### 2.1 Ability behaviours: extra keys survive

`DMHub Game Rules/ActivatedAbility.lua:687-698`:

```lua
function ActivatedAbility.RegisterType(args)
    args.index = #ActivatedAbility.Types+1
    local doc = ActivatedAbility.TypesById[args.id]
    if doc ~= nil then
        args.index = doc.index
    end

    ActivatedAbility.Types[args.index] = args
    ActivatedAbility.TypesById[args.id] = args

	ActivatedAbility.OnTypeRegistered()
end
```

The args table itself is stored, so `block = {...}` is kept. Two notes:

- Re-registering an id **replaces** the table. It does not merge. No id is registered twice
  today (checked across all 101 call sites), so this is safe, but the brief's "survives
  re-registration" is only true if the new registration carries the block.
- `ActivatedAbilityTypeEntry` (`ActivatedAbility.lua:119-126`) lists `id, text,
  createBehavior, index, hidden, mono, canHaveDC`. Reading `entry.block` without a
  `--- @field block?` line is a LuaLS `undefined-field`, and the ceiling is zero.

### 2.2 Modifiers: only `{id, text}` is kept

`DMHub Game Rules/CharacterModifier.lua:108-117`:

```lua
function CharacterModifier.RegisterType(id, text)
	CharacterModifier.DeregisterType(id) --remove any existing entry.
	CharacterModifier.Types[#CharacterModifier.Types+1] = {
		id = id,
		text = text,
	}

	CharacterModifier.TypesById[id] = CharacterModifier.Types[#CharacterModifier.Types]
	...
end
```

- Behaviour lives in `CharacterModifier.TypeInfo[id]` (`:433`), read everywhere as
  `CharacterModifier.TypeInfo[self.behavior] or {}` (for example `:3266`, `:4305-4309`).
- `DeregisterType` (`:120-144`) removes the entry from `Types` and `TypesById` but **leaves
  `TypeInfo`**. Draw Steel deregisters several 5e types (`MCDMRules.lua:1729-1734`). So the
  shelf must be built by walking `CharacterModifier.Types` and then looking up `TypeInfo`,
  never by walking `TypeInfo`.

### 2.3 Choices: a private table in a UI file

`Draw Steel UI/DSClassEditor.lua:3-7`:

```lua
local g_registeredCharacterChoices = {}

function CharacterChoice.RegisterChoice(options)
    g_registeredCharacterChoices[options.id] = options
end
```

- The options table is stored as given, so a `block` key would be kept, but nothing outside
  this file can reach it.
- The older copy in `DMHub Compendium/ClassEditor.lua:5-9` is commented out as dead code.
- Six callers register choices (skills, languages x2, deities x2, companion).
- Registered choices are created with `t.Create{source = ..., classid = ...}` (`:1110-1114`).
  Built-ins use different constructors: `CharacterFeatChoice.CreateNew()` (`:1139`),
  `CharacterSubclassChoice.CreateNew{classid = classid}` (`:1124`), and so on. A shared
  registry needs one `create(ctx)` function per choice.
- The perk choice is the hard-coded `'feat'` entry (`:1052-1054`, handled at `:1138-1140`).

### 2.4 Load order

`main.lua` is informational and may be stale, but it shows the order the cloud file lists had:
`DMHub Utils` (line 32) -> `CharacterModifier` (171) -> `Class` (177) -> `DSClassEditor`
(421) -> `DSSkillChoice` (453) -> `MCDMAbilityRollBehavior` (459) -> `MCDModifyPowerRolls`
(486).

The examples call `Block.Choice{...}` inside registrations at file-load time. So the file
that defines `Block` must load **before `CharacterModifier.lua`**. That means it belongs in
`DMHub Utils`, and it must not touch `gui`. Confirm the real order against the CodeMod records
before registering the file.

## 3. Proposed file layout

All new files are registered through `mcp__dmhub__register_lua_file`. None is added by editing
`main.lua`.

| File | Mod | Loads | Holds |
|---|---|---|---|
| `Block.lua` | `DMHub Utils` | before `DMHub Game Rules` | Slot constructors (`Block.Choice` ...), forms, safe field access, the declaration classes for LuaLS. Pure data, no `gui`. |
| `BlockRegistry.lua` | `DMHub Game Rules` | after `Class.lua` | Collects blocks from the three type registries plus wrappers and recipes. `BlockEditor.RegisterWrapper`, `RegisterRecipe`, `RegisterHost`. Read-back, write, validation, prose. No `gui`. |
| `BlockRoundTrip.lua` | `DMHub Game Rules` | after the registry | The round-trip check and the registry export (D9). No `gui`. |
| `BlockEditorUI.lua` (later split) | new mod `Block Editor`, or `Draw Steel UI` | after `Draw Steel Core Rules` | Shelf, stack, block and slot panels, drag and drop, status, preview. Knows slot types. Knows **no** block ids. |
| Host declarations | beside each record type | with that type | `BlockEditor.RegisterHost{...}` calls. |

Rule for the UI file, enforceable in review: **it must not contain a behaviour id, a modifier
id, a choice id or a type name as a string literal.** A grep in CI can check this.

## 4. Registration surface, capability by capability

Each row below names the declaration field, says whether the prototype's logic can be
expressed purely as data, and names the hook where it cannot.

### 4.1 Where a declaration lives

| Family | Where | Preserved today? | Change needed |
|---|---|---|---|
| Modifier | `block = {...}` or `blocks = {...}` inside `CharacterModifier.TypeInfo.<id> = {...}` | Yes (open table) | None. Optional: a `---@class` for TypeInfo entries. |
| Ability step | `block` / `blocks` in `ActivatedAbility.RegisterType{...}` | Yes (`ActivatedAbility.lua:694-695`) | Add `--- @field block?` and `blocks?` to `ActivatedAbilityTypeEntry`. |
| Choice | `block` in `CharacterChoice.RegisterChoice{...}` | Stored, but unreachable | C2: move registry, add accessor, register built-ins. |
| Wrapper / logic | `BlockEditor.RegisterWrapper{...}` | New | New code only. |
| Recipe | `BlockEditor.RegisterRecipe{...}` | New | New code only. |
| Host | `BlockEditor.RegisterHost{...}` | New | New code only. |

Modifier declaration, corrected for A1:

```lua
CharacterModifier.RegisterType('conditionimmunity', "Condition Immunity")   -- unchanged

CharacterModifier.TypeInfo.conditionimmunity = {
    -- existing hooks stay exactly as they are
    createEditor = function(modifier, element) ... end,

    block = {
        label = "Can't gain a condition",
        group = "def",
        desc = "You can't be given the conditions you name.",
        sentence = "You can't be {conditions}",
        slots = {
            conditions = Block.Many{ field = "conditions", from = "charConditions", form = "list", conj = "or" },
        },
    },
}
```

### 4.2 Shelf label, group, colour, description

| Field | Notes |
|---|---|
| `label`, `desc` | Plain strings. Fully declarative. |
| `group` | An id. Groups themselves are registered: `BlockEditor.RegisterGroup{ id = "rolls", text = "Rolls", color = "#7d4aa3", glyph = "dice-six", order = 40 }` *(revised 2026-11-26: fixed hex plus a glyph, see the implementation plan section 13)*. Colour belongs to the group, and should be a ThemeEngine token, not a hex value (see `DefaultStyles.md`). A block may override with `color`. |
| `shelf = false` | Hides a block from the shelf but still reads saved records (the prototype's `shelf: false`, `app.js:475`). |
| `unique = true` | Puts it in the Unique group (standing decision). |
| `featureKind` | Optional. Replaces the prototype's hard-coded `kindLabel` chain (`app.js:945-947`), which names `trigger`, `ability` and `growing` in editor code. |

Today's shelf metadata is hard-coded in the pickers: `BEHAVIOR_METADATA`
(`AbilityEditorBehaviorPicker.lua:45`) and `MODIFIER_METADATA`
(`AbilityEditorModifierPicker.lua:71`). These are exactly the per-editor tables the owner wants
gone. They become fallbacks for one release and are then deleted.

### 4.3 Sentence and prose

| Field | Notes |
|---|---|
| `sentence` | Template with `{slot}` and `{verb|verbs}`. Declarative. |
| `prose` (string) | Different book wording. Declarative. |
| `prose` (function `(values, w)`) | The hook for value-dependent wording. |
| `plural` | **New, proposed.** `{amount:square|squares}` in a template picks the word by the slot's number. Covers most "1 square / 3 squares" cases without a function. The prototype does this by hand in a render function (`app.js:474`: `+f.radius === 1 ? "square." : "squares."`). |
| `{?slot ... }` | **New, proposed.** A span shown only when the slot has a value: `"deal {amount} extra{? {type}} damage"`. Covers most conditional wording. |

Checked against the code:

- Formula to English exists: `GoblinScriptProse.Render(formula, ctx)`
  (`DMHub Utils/GoblinScriptProse.lua:1118`). It returns the raw formula on failure, which is a
  safe fallback.
- Behaviour prose is keyed by **typeName**, not id (`GoblinScriptProse.lua:2174`, `:2685`), and
  `RenderBehaviour` has a four-step fallback chain (`:2677-2705`). Add "the type's block prose"
  as step 0 and leave the rest. That is a small additive change (C5).
- Pass the prose function the **slot values**, not the raw record. The brief's examples read
  `rec.resistances` directly. On a game-typed record a missing field raises (CLAUDE.md, "Reading
  a missing method on a game-typed instance raises"). If a prose function must see the record,
  it uses `rec:try_get(...)`.

### 4.4 Slots and field mapping

The decided three levels (D2) are sound. Details that must be fixed in the implementation:

| Point | Why |
|---|---|
| `field` reads go through a safe getter | `Block.Get(rec, "a.b")` uses `try_get` on game types and plain indexing on plain tables. The same helper already exists as a local in `GoblinScriptProse.lua:2176-2187`. |
| `field` writes set the key directly | Setting an unknown key on a game type is fine. Only reads raise. |
| `default` is the value in a **new** block, and also the "absent" value on read | Needed so "field missing" and "field equals default" open the same, and so an untouched slot is not written. |
| A slot may claim several fields | `fields = { "resourceCostType", "resourceCostAmount" }` on `Block.Cost`. The claims list feeds "Advanced editor (N)". |
| `from` with a table name | Read with `dmhub.GetTable(name)` and `unhidden_pairs` at open time, never at load time. Tables are not ready at load. |
| `from` with a Lua list | Fine at load **only if the list is defined earlier**. `ActivatedAbilityPowerRollBehavior.s_modificationTypes` is at `MCDMAbilityRollBehavior.lua:2479`, which loads before `MCDModifyPowerRolls.lua`. To be safe, allow `from = function() return list end`. |

Note: `s_modificationTypes` contains `minusthree` twice (`:2506-2507`). The load-time check for
`only` / `words` ids should also report duplicate ids in a `from` list.

### 4.5 Read-back, unclaimed fields, and the round-trip rule

The brief says round trip is "tested, not trusted". That is right, but it is not enough. Make it
true **by construction** as well:

1. **Open:** `values = decl.read(rec)` (or the per-slot getters). Keep a copy as `opened`.
2. **Edit:** the author changes slots. The editor tracks which slots differ from `opened`.
3. **Save:** only for changed slots, call the slot setter (or `decl.write(values, rec, changed)`).
   A block nobody touched **writes nothing**.

This removes a whole class of failures the brief already found (Primordial Strength storing
the same test twice) and the ones in A4 (`true` rewritten as `"1"`, absent rewritten as `""`).

"Advanced editor (N)":

- Game-type instances are plain tables with a metatable. `DeepCopy` walks them with `next`
  (`DMHub Utils/Utils.lua:1652`), so the framework can list a record's stored keys the same
  way.
- N = stored keys, minus the keys claimed by the block's slots, minus a framework list of
  bookkeeping keys per family (`guid`, `sourceguid`, `name`, `source`, `description`,
  `behavior`, `domains`; see how a modifier is created at `CharacterFeature.lua:559-567`),
  minus keys starting with `_tmp_`, minus keys equal to the type's `init` defaults.
- "Equal to the `init` default" needs a baseline: build one throwaway record with
  `typeInfo.init` (`CharacterFeature.lua:568-571`) and compare. Without this, every `power`
  block would show "Advanced editor (1)" for `keywords = {}` (`MCDModifyPowerRolls.lua:487`).
- The Advanced editor is the existing form: `TypeInfo[id].createEditor(mod, element)`
  (`CharacterFeature.lua:586-590`) for modifiers and `EditorItems` for behaviours (105
  references). No change is needed to mount them.

`read` may return `nil` to refuse (decided). Add: `read` may also return a second value, a list
of field names it could not show, so a record is partly shown instead of wholly refused.

### 4.6 Validation ("things to finish")

| Field | Notes |
|---|---|
| `required = true` on a slot | Declarative. Covers most of the prototype's checks. |
| `check = function(values, report, ctx)` | The hook. `report(text, { fix = { label, run } })`. |
| `children.minimum = 1` | Declarative "has nothing inside" for wrappers. |

The prototype's `featureIssues` names seven block types in editor code (`app.js:1877-1894`:
`growing`, `aura`, `onlyIf`, `ability`, `trigger`, `abilityChoice`, `skills`). Every one of
them can move to that block's `check`. Class-level checks (`app.js:1910`, `:1914`: "has a
resource", "has a subclass choice") belong to the **host's** `check`, which is also a
registration, so that is acceptable.

### 4.7 Hosts, contexts and nesting

| Field | On | Notes |
|---|---|---|
| `family` | block | Set by the registry from where the block was declared. Not typed by hand. |
| `tags` | block | Free tags: `"choice"`, `"wrapper"`, `"container"`, `"rollChange"`. |
| `hosts = { "ability" }` / `notHosts` | block | Rarely needed. Limits a block to some hosts. |
| `accepts = { families, tags, notTags }` | a `Block.Blocks` slot or a host stack | What may go inside. |
| `canAccept = function(childDecl, ctx)` | same | The hook, for rules data cannot say. |
| `supportsFilter` | modifier block | See below. |

The prototype enforces nesting in editor code: `listAccepts` (`app.js:1604-1614`) and
`sentenceMenu` (`:1713`) test `SENT[type].choice || wrapper || container` and the special list
flags `inIf` and `combo`. Under the plan the Logic wrapper declares it:

```lua
BlockEditor.RegisterWrapper{
    key = "onlyIf", label = "Logic", group = "if",
    desc = "The blocks inside apply only while something is true.",
    sentence = "Only if {cond}",
    slots = {
        cond = Block.Test{ context = "you", required = true },
        body = Block.Blocks{ accepts = { families = { "modifier" }, notTags = { "wrapper", "container" } },
                             minimum = 1 },
    },
    -- Called once per child record on save; the child must have said it supports a filter.
    wrap = function(values, childRecord) Block.AndFilter(childRecord, "filterCondition", values.cond) end,
    prose = function(values, w) return "If " .. w.test(values.cond) .. ", " .. w.children("body") end,
}
```

"Never inside itself" is a framework rule for every wrapper, not a declaration.

**Filter support is not universal.** `filterCondition` is honoured only where a type's code
calls `PassesFilter`, and `PassesFilter` returns `true` without testing when
`typeInfo.filterRequiresRoll` is set (`CharacterModifier.lua:4305-4313`). So a block must
state whether Logic can wrap it. Default: a modifier block is wrappable only if it sets
`supportsFilter = true`. This needs a per-type check when each block is written.

**Reading Logic back is ambiguous.** The prototype saves a Logic block by AND-ing its test
into each child's `filterCondition` (`app.js:1066`, `:1081`). Nothing in the record says the
children were grouped. Proposed rule: on open, consecutive sibling modifiers with the
**identical** `filterCondition` string are shown inside one Logic block when the string parses
as a known test; otherwise each block shows its own "Only if" line. Because untouched blocks
are not rewritten (4.5), either display is safe. Owner's call: see section 10.

### 4.8 Combine and merge rules

**The prototype's version, to avoid.** `rollCombo` is a block type the editor knows by name.
It appears in the grouping key (`app.js:785`), `combinableGroups` (`:788`), `combineBlocks`
(`:799`), `uncombine` (`:813`, which also special-cases `child.type === "edge"`), drop
acceptance (`:1611`, `:1697-1700`), the compiler (`:1059-1065`), prose (`:966`), the add menu
(`:1713`) and the block renderer (`:1727`, `:1740-1750`). That is nine editor-side special
cases for one type.

**The registration hook.** Combining is a property of a **type whose blocks write different
fields of one record**. Declare it once on the type, beside `blocks`:

```lua
CharacterModifier.TypeInfo.power = {
    -- existing hooks unchanged ...

    blocks = {
        { key = "edge", label = "Edge or bane on rolls", ...,
          claims = { "modtype" },
          match = function(rec) return Block.OneOf(rec:try_get("modtype", "none"), "edge", "double_edge", "bane", "double_bane") end,
          part = { sentence = "have {modtype}", exclusive = "modtype" } },
        { key = "outcome", label = "Change the outcome", ...,
          claims = { "modtype" },
          match = function(rec) return Block.OneOf(rec:try_get("modtype", "none"), "tier3", "tier1", "tierup", "tierdown") end,
          part = { sentence = "{modtype}", exclusive = "modtype" } },
        { key = "damage", label = "Extra damage", ...,
          claims = { "damageModifier", "damageModifierType" },
          match = function(rec) return rec:try_get("damageModifier", "") ~= "" end,
          part = { sentence = "deal {damageModifier} extra {damageModifierType} damage" } },
        { key = "surges", label = "Extra surges", ...,
          claims = { "surges", "surgesCanBeKept" },
          match = function(rec) return rec:try_get("surges", "") ~= "" end,
          part = { sentence = "gain {surges:surge|surges}{surgesCanBeKept}" } },
    },

    combine = {
        label    = "Combined roll change",
        sentence = "Your {keywords} ability rolls:",
        -- Slots every part shares; set once on the combined block.
        shared   = { "keywords", RollOptions },
        -- Blocks with the same key may combine. nil = this block can't.
        key = function(values)
            if values.rollType ~= "ability_power_roll" then return nil end
            return Block.SetKey(values.keywords)
        end,
        -- When shared values differ, the first block's are used and the author is told.
        conflict = "first",
    },
}
```

What the framework does with it, generically:

| Step | Rule (no type names involved) |
|---|---|
| Offer "Combine" | Siblings of one type with `combine`, equal `combine.key(values)`, and at most one part per `exclusive` tag. |
| Combined block | One record. Shared slots shown once. Each part shows its `part.sentence`. |
| Add a part | Offers that type's blocks whose `exclusive` tag is still free. |
| Drop acceptance | Same test as "add a part". |
| Save | Run each part's slot writes on the **same** record, then the shared slots. |
| Split / take out | Clone the record's shared fields into a new record per part. |
| Prose | Join part sentences with the list helper: "have an edge, deal 2 extra damage and gain 1 surge". |
| Open a saved record | Ask every block's `match`. One match = a plain block. Two or more and the type has `combine` = a combined block. Fields no matching block `claims` = "Advanced editor (N)". |

`exclusive = "modtype"` expresses "at most one `modtype`" as data. The engine really does hold
one: `modtype` is a single field read once per roll (`MCDModifyPowerRolls.lua:906`,
`:935`), while `damageModifier` (`:1014`), `surges` with `surgesCanBeKept` (`:1375-1381`) and
`potencymod` (`:1384`) are independent fields.

This replaces Q2's "first match wins" (A3). For types without `combine`, "exactly one match,
most specific first" still applies, so the `attribute` example is unaffected.

### 4.9 Roll-option lines

`Block.Group{ lines, slots, read, write }`, listed in a block's `includes` (decided). It is
declarative apart from its `read`/`write`. Define `RollOptions` in `MCDModifyPowerRolls.lua`
next to the fields it maps, not in the framework: the framework must not know what
`activationCondition` means.

Corrected mapping, from the code:

| Stored | Meaning | Source |
|---|---|---|
| `activationCondition == true` | always | `MCDModifyPowerRolls.lua:721`, `:1921` |
| `activationCondition == false`, `""`, or absent | never (the player chooses) | `:639`, `:673`, `:1918` |
| any other string | GoblinScript test | `:751` |
| `activationAfterRoll` is a string | after-the-roll option; block refuses | `:644`, `:1517-1518` |
| `displayCondition` | "Offered when"; `""` = always offered | `:10`, `:824` |
| `resourceCostType` not `"none"` | costs a resource | `CharacterModifier.lua:3677` |

```lua
write = function(v, rec, changed)
    if changed.offer then rec.displayCondition = v.offer or "" end
    if changed.selected or changed.tick then
        if v.selected == "when" then rec.activationCondition = v.tick or ""
        elseif v.selected == "never" then rec.activationCondition = false
        else rec.activationCondition = true end
    end
    if changed.selected or changed.cost then
        if v.selected == "cost" then
            rec.resourceCostType = v.costRes; rec.resourceCostAmount = v.costN
        else
            rec.resourceCostType = "none"
        end
    end
end,
```

### 4.10 Drag-and-drop acceptance

Declarative: it is the same `accepts` / `canAccept` / `combine` test as the add menu, called
through one function, `BlockEditor.CanPlace(decl, listContext)`.

The engine supports this without change: `draggable`, `dragTarget` and
`canDragOnto(thisPanel, targetPanel)` exist on panels (`Definitions/Panel.lua:65-67`) and are
used in `DMHub Core UI/DockablePanel.lua:1119` and `CommandBuilder.lua:1696`. Each insert point
("+ add" and the gap between blocks) is a small `dragTarget` panel carrying its list context in
`data`. Every drag also needs a click path (decided), so "Move up / Move down / Move to..."
menu items use the same `CanPlace`.

### 4.11 Formula slots with docs

Fits as-is. `gui.GoblinScriptInput(options)` takes `documentation`
(`DMHub Core Panels/GoblinScriptEditor.lua:61-67`).

One correction: the brief writes examples as pairs, `{ "Level", "Your level." }`. The real
shape is `{ script = "...", text = "..." }`, with `help`, `output`, `subject`, `domains`
(`CharacterModifier.lua:2963-2975`). `Block.Formula{ docs = ... }` should take the real shape
and pass it through untouched, so no converter exists to drift.

### 4.12 Test slots

The prototype stores a test as a small tree and compiles it to GoblinScript (`testGs`,
`app.js:530`). Saved records hold only the GoblinScript string. So `Block.Test` needs **string
to tree** on open. A tokenizer and parser already exist as locals in
`GoblinScriptProse.lua` (`tokenise` `:136`, `parseFormula` `:545`), with public walkers such as
`WalkLiteralComparisons` (`:1531`). The plan: a test-pattern registry
(`Block.RegisterTest{ id, context, toScript, fromAst, prose }`) on top of that parser. A string
no pattern recognises shows as a raw formula chip and is kept unchanged. This is the largest
single piece of new logic; it needs a small additive export from `GoblinScriptProse` (C6).

## 5. Hosts

### 5.1 What the host owns and what blocks own

| Host owns | Blocks own |
|---|---|
| Which record type and table it edits | Label, group, sentence, prose |
| Header rows (fixed fields) | Slots and field mapping |
| Which stacks exist and where they live in the record | Validation of their own values |
| Which families and tags each stack accepts | What they accept inside themselves |
| Point of view (D7) | Combine rules |
| Tabs and their record sources | Advanced-editor fallback |
| Record-level checks | |
| Save: when and how the record uploads | |

A host never names a block. If a host needs a particular block to exist (the class host's
"Choose your subclass"), it says so with a tag: `requires = { tag = "subclassChoice" }`.

### 5.2 The feature layer (correction A5)

Records store features like this (`Class.lua:28-31`, `CharacterFeature.lua:572-573`):

```
Title.modifierInfo            : ClassLevel
  .features[]                 : CharacterFeature | CharacterFeatureList | CharacterChoice | CharacterSingleFeat
     CharacterFeature.modifiers[] : CharacterModifier      <- modifier blocks
     CharacterChoice                                      <- choice blocks (siblings, not children)
     CharacterFeatureList.features[]                      <- a group of the above
```

The prototype decides the record shape in editor code (`app.js:1086-1099`): modifiers only =
a feature; one choice alone = that choice; a mix = a `CharacterFeatureList` holding a hidden
feature plus the choices. That rule is generic, so it belongs in the framework as a named
**feature layer**, declared by the host:

```lua
BlockEditor.RegisterHost{
    id = "title", record = "Title", table = "titles",
    pointOfView = "you",
    header = {
        { field = "echelon", label = "Echelon", slot = Block.Choice{ options = { {"1","1"}, {"2","2"}, {"3","3"}, {"4","4"} } } },
        { field = "prerequisite", label = "Earned when", slot = Block.Text{} },
    },
    stacks = {
        { features = function(rec) return rec:GetClassLevel().features end,   -- the list of features
          accepts = { families = { "modifier", "choice", "logic", "recipe" } } },
    },
}
```

- `features = fn` returns the feature list. `Title` inherits `CharacterFeat` (`Titles.lua:14`), whose
  `GetClassLevel()` creates the list on demand (`Feat.lua:86-92`).
- The framework's feature layer maps **one authored feature** to one of the three record
  shapes, and back. It uses each block's `family` to know that a choice becomes a sibling
  record. It names no types beyond the four feature-list types, which are the storage format.
- One-feature hosts (ongoing effects, conditions) declare `modifiers = fn` instead and skip
  the layer.
- Reading back the "list with a hidden feature" shape must be exact: only regroup when the
  list matches the shape the layer writes. Any other `CharacterFeatureList` opens as a group.

### 5.3 Class and subclass hosts

```lua
BlockEditor.RegisterHost{
    id = "class", record = "Class", table = "classes",
    pointOfView = "you",
    lanes = { kind = "levels", get = function(rec, n) return rec:GetLevel(n).features end, count = 10 },
    tabs = {
        -- Each subclass is its own record in another table.
        { id = "subclasses", host = "subclass", table = "subclasses",
          filter = function(sub, class) return sub.primaryClassId == class.id end,
          create = function(class) return Class.CreateNew{ isSubclass = true, primaryClassId = class.id } end },
    },
}

BlockEditor.RegisterHost{
    id = "subclass", record = "Class", table = "subclasses",
    pointOfView = "you",
    lanes = { kind = "levels", get = function(rec, n) return rec:GetLevel(n).features end, count = 10 },
}
```

Checked:

- Subclasses are `Class` records with `isSubclass` and `primaryClassId` (`Class.lua:11-13`,
  `:68-69`), stored in the `subclasses` table (`Class.lua:1232`).
- `CharacterSubclassChoice` offers every subclass whose `primaryClassId == self.classid`
  (`Class.lua:1229-1247`). Today's editor lists them the same way
  (`DSClassEditor.lua:1922-1924`).
- **Each tab saves its own record** with its own
  `dmhub.SetAndUploadTableItem(tableName, item)` (`DSClassEditor.lua:1180-1187` shows today's
  deferred-upload pattern). A class save and a subclass save are separate uploads; there is no
  transaction across them. (Linking subclasses from other classes was removed from the design.)
  The host must show unsaved state per tab.

### 5.4 Perk, title and ability hosts

- **Perk** and **title** are one-list hosts like the example above (`Feat.lua:279`,
  `Titles.lua:226-231`).
- **Ability**: the stack is `ability.behaviors`, the family is `step`, and point of view is
  "the target". Its header (keywords, action, distance, target) is the largest header of any
  host. The ability host is also used **inside** `Block.Ability` slots, so it must be mountable
  as a dialog over another host.

## 6. Editor-side special cases in the prototypes (flagged)

Every row is something the Lua build must not copy.

| Prototype code | What it hard-codes | Registration hook instead |
|---|---|---|
| `app.js:785-830`, `:1059-1065`, `:1697-1700` | `rollCombo`, `comboHost`, `edge` | `combine = {...}` on the type (4.8) |
| `app.js:962-966` | prose for `onlyIf`, `aura`, `growing`, `ability`, `trigger`, `rollCombo` | wrapper `prose(values, w)` with `w.children(...)`; `prose = false` for blocks with no sentence |
| `app.js:1054-1080` | compile for `aura`, `onlyIf`, `growing` | wrapper `wrap` / `write`; children via `Block.Blocks` slots |
| `app.js:856` | `growing` has rows of child lists | several `Block.Blocks` slots; the framework finds child lists from the declaration |
| `app.js:1604-1614`, `:1713` | no choices in Logic; only roll changes in a combo | `accepts` / `canAccept` (4.7) |
| `app.js:1877-1894` | per-type "things to finish" | `check` on each block (4.6) |
| `app.js:945-947`, `:983` | feature kind and name from `trigger`, `ability`, `abilityChoice` | `featureKind`, `featureName(values)` on the block |
| `app.js:846-847` | collects ability names from `ability`, `trigger`, `abilityChoice` | `Block.Ability` slot type reports the names it holds |
| `app.js:927-930` | data migration per type | `migrate(values, fromVersion)` on the block |
| `app.js:1086-1099` | record shape from block mix | the framework feature layer (5.2); generic |
| `app.js:1910`, `:1914` | class needs a resource and a subclass choice | host `check` with `requires = { tag = ... }` |
| `ability-blocks-stack.html:1148`, `:1266`, `:1842`, `:1957` | `switch (x.type)` for compile, render, prose, import | one declaration per step; no switch |
| `DSClassEditor.lua:1035-1059`, `:1109-1146` (today's Lua) | seven built-in choices in a dropdown and an if/elseif chain | C2: register them |
| `AbilityEditorBehaviorPicker.lua:45`, `AbilityEditorModifierPicker.lua:71` (today's Lua) | shelf metadata keyed by id inside pickers | `block.label/group/desc` |

## 7. Infrastructure changes needed

All are additive Lua changes. Listed smallest-viable first. **None is made by this review.**

| # | Change | Smallest version | Files | Size |
|---|---|---|---|---|
| C1 | Type the `block` key on behaviours | Add `--- @field block? BlockDecl` and `--- @field blocks? BlockDecl[]` to `ActivatedAbilityTypeEntry` | `DMHub Game Rules/ActivatedAbility.lua:119-126` | 2 lines |
| C2 | A reachable choice registry | Move `RegisterChoice` and its table into `Class.lua` next to `CharacterChoice` (`:37`); add `CharacterChoice.RegisteredChoices()`; add an optional `create(ctx)`; register the seven built-ins; make `DSClassEditor.lua` read the accessor | `DMHub Game Rules/Class.lua`, `Draw Steel UI/DSClassEditor.lua:3-7, 1035-1146`, `DMHub Game Rules/Feat.lua` (perk choice registration) | about 80 lines; the only change that touches today's editor behaviour |
| C3 | Type TypeInfo entries (optional but recommended) | `--- @class CharacterModifierTypeInfo` with `block?`, `blocks?`, `combine?` and the existing hooks as optional fields; annotate `CharacterModifier.TypeInfo` | `DMHub Game Rules/CharacterModifier.lua:433` | about 20 lines; run the full type check, since every TypeInfo literal is then checked |
| C4 | Safe field access as shared code | `Block.Get(rec, path, default)` / `Block.Set(rec, path, value)` in the new `Block.lua` | new file | new |
| C5 | Block prose in the behaviour prose chain | In `RenderBehaviour`, try the type's block prose before `behaviourProse[typeName]` | `DMHub Utils/GoblinScriptProse.lua:2677-2690` | about 10 lines; needs a way from behaviour instance to type id (`behavior` field, read with the existing `tryGet`) |
| C6 | Expose the GoblinScript parser for test read-back | A public `GoblinScriptProse.Parse(formula)` returning the AST the file already builds (`getParsed`, used at `:1121`) | `DMHub Utils/GoblinScriptProse.lua` | about 10 lines |

Not needed, despite the brief: any change to `CharacterModifier.RegisterType` (A1), and any
engine change.

Each new file goes through `mcp__dmhub__register_lua_file` with `before`/`after` ordering, and
`python tools/typing/annotate_gametypes.py` if it registers a game type. The framework should
register **no** new game type for editor state: block values are plain Lua tables held in panel
`data`, and only real records are saved.

## 8. Fit check by risk

| Risk | Finding | Rating |
|---|---|---|
| **Serialization** | Declarations live on registries, not on records, so nothing new is serialized. Editor state must stay out of records; if any must ride on a record, use a `_tmp_` key (skipped by serialization and by `DeepCopy`'s deep walk, `Utils.lua:1657-1658`). | Fits |
| **Unknown-field reads** | The biggest practical trap. Every example in `REGISTRY_EXAMPLES.md` that reads `rec.x` in `read`, `match` or `prose` can raise on a real record. Example: imported power modifiers lack `activationCondition` (`MCDModifyPowerRolls.lua:636-639`). Rule: declarations use `rec:try_get`, and the framework wraps every `read`, `match`, `check` and `prose` call in `pcall`, turning an error into "open in the Advanced editor" plus a developer log line. | Needs care, no infra change |
| **Typing at zero** | (1) C1 is required. (2) Calling `RegisterType` with a third argument would be `redundant-parameter`; A1 avoids it. (3) Declaration functions should annotate their record: `---@param rec CharacterModifier`. Behaviour-specific fields are already listed as optional fields on the class (`CharacterModifier.lua:26-64`); new ones read by blocks must be added there or read with `try_get`. (4) Slot constructors return typed classes (`BlockSlot`, `BlockDecl`) defined in `Block.lua`. (5) `lowercase-global` is on: `Block` and `BlockEditor` are upper-case, so fine. | Small additive |
| **Panel count** | The class editor measured about 3 ms per panel inside `vscroll`, and a 20 s freeze before lazy building (`DSClassEditor.lua:971-977`). A block is roughly 1 row + 1 grip + 1 menu + 2 panels per slot. A 30-block feature is 200-300 panels: about 1 s if built eagerly. Rules: build a feature's blocks only when it is opened (reuse the `EnsureBuilt` pattern, `:992-1004`); show closed features as one prose label; never rebuild the stack on change (`UI_BEST_PRACTICES.md:222-252`); refresh one block with `FireEventTree`. The decided "redraw only the block that changed" is mandatory, not an optimisation. | Fits with discipline |
| **Sentence layout** | A sentence is a horizontal `wrap = true` row of labels and chips. Wrap only works against a bounded axis (`UI_BEST_PRACTICES.md:588-590`), so block rows need a fixed or percent width. Text and chips cannot share one text run; each literal span between slots is its own label, so long literal spans wrap as a unit. Keep literal spans short. | Fits, visual limits |
| **Undo** | These are compendium records, saved with `dmhub.SetAndUploadTableItem` (`DSClassEditor.lua:1183-1186`). `ModifyProperties` is for token properties and does not apply. There is no undo stack for compendium editors today. The framework owns undo: a stack of `DeepCopy` snapshots of the open record, cleared on save. Where a host is mounted inside the character sheet (item features on a token), it must follow the sheet's direct-edit rule instead. | Framework must build it |
| **Upload and diff** | `SetAndUploadTableItem` uploads the whole item (`Definitions/dmhub.lua:670-675`). Today's editor defers the upload until the author leaves the record (`DSClassEditor.lua:1180-1187`). Keep that. Do not upload on every slot change. | Fits |
| **Save conflict ("Someone else saved this")** | **Unverified.** I found no per-item revision or modified-time API for data tables in `Definitions/dmhub.lua`. A fallback that needs no engine support: keep the `DeepCopy` taken at open, and before saving compare it with the table's current item using `dmhub.DeepEqual` (`Definitions/dmhub.lua:1163`). | Open question |
| **Round-trip check** | `dmhub.DeepEqual` and `dmhub.ToJson` (`:1141`) exist, and `dmhub.WriteTextFile` (`:488`) can write the report and the D9 registry export. The check runs inside the app (it needs the compendium). The repo's `tests/` folder runs plain Lua with stubbed globals (`tests/target_characteristic_test.lua:1-20`), which suits unit tests of `Block.lua` forms and templates, since that file has no `gui` dependency. | Fits |
| **ASCII only** | The prototypes use Unicode punctuation in strings (`app.js:451`, `:860`). Lua strings must use ASCII: `...`, `-`, `x`. | Fits with care |

## 9. Phased build order

### Phase 0: groundwork (no UI)

1. `Block.lua` in `DMHub Utils`: slot constructors, forms (`set`, `list`, `csv`, `bool01`),
   `Block.Get` / `Block.Set`, template parsing (`{slot}`, `{a|b}`, `{n:one|many}`, `{? }`).
2. C1, C3 typing lines.
3. `BlockRegistry.lua`: collect from `CharacterModifier.Types` + `TypeInfo`, from
   `ActivatedAbility.Types`, and wrappers. Generic grey block for types with no declaration (D5).
4. Unit tests for 1 under `tests/`, run with the repo's Lua.

### Phase 1: the thin vertical slice (one modifier type, end to end)

**Type: `conditionimmunity`** (`CharacterModifier.lua:1523-1534`). It is field-for-field with
one `Many` slot, so it proves the pipeline with no Level 3 code. Second type for the slice:
`attribute` with a single "Change a stat" block, which adds a Choice and a Formula slot and the
"decreases by" conversion.

Steps:

1. Add `block = {...}` to the `conditionimmunity` TypeInfo literal. Nothing else changes in
   that file.
2. Registry functions: `Read(rec) -> values`, `Write(values, rec, changed)`,
   `Unclaimed(rec) -> keys`, `Prose(rec, pov)`, `Check(rec)`.
3. A minimal stack panel mounted as an **alternative view** inside
   `CharacterFeature:EditorPanel` (`CharacterFeature.lua:432`), behind a `setting{}` toggle that
   defaults off. Today's form stays the default and is the Advanced editor.
4. No shelf, drag, combine or wrappers yet. An "add" menu built from the registry is enough.

**How to prove it works:**

| Gate | Pass condition |
|---|---|
| G1 Round trip, untouched | For every compendium record with a `conditionimmunity` modifier: `before = DeepCopy(rec)`; open as blocks; save; `dmhub.DeepEqual(before, rec)` is true. Compared field by field, not by meaning. |
| G2 Round trip, forced | Same records, but call every slot setter with the value just read. Records that differ are listed. This is the "earn the block" check from the brief. |
| G3 Edit parity | Make one edit with the block, the same edit with the old form on a copy; the two records are `DeepEqual`. |
| G4 Unclaimed | A record with a `filterCondition` shows "Advanced editor (1)", opens the old form, and the filter survives a block edit. |
| G5 No editor knowledge | `grep` the UI file for `conditionimmunity` and `attribute`: zero hits. |
| G6 Extension test | A second developer adds a block for a third simple type by editing only that type's file. Time it. |
| G7 Type check | `python tools/typing/check.py --all` is clean. |
| G8 Performance | Open the largest real feature (Berserker's Chaos Incarnate, 7 modifiers) and a synthetic 30-block feature; measure build time. |

G1 and G2 run from a developer command that walks the tables with `dmhub.GetTable` and
`unhidden_pairs`, and writes a report with `dmhub.WriteTextFile`.

### Phase 2: the framework proper

Hosts and the feature layer (5.2), C2 (choices), Logic wrapper, the shelf with groups and
search, validation and Status, the prose preview, undo. First hosts: title and perk. Then the
remaining one-list editors.

### Phase 3: power roll blocks

`RollOptions` group, the `blocks` list for `power`, claims-based read-back and `combine`
(4.8), `Block.Test` with the parser export (C6). Gate: the brief's coverage numbers (727, then
about 1,215 of 1,394) reproduced by the round-trip check, counting combined records.

### Phase 4: class and subclass hosts

Lanes, tabs, separate saves per record, the subclass choice block, drag and drop between lanes.

### Phase 5: ability steps

`step` family blocks, the ability host, `Block.Ability` slot, C5 (block prose into
`RenderBehaviour`), then retiring `BEHAVIOR_METADATA`, `MODIFIER_METADATA` and the moved
`behaviourProse` templates.

### Phase 6: embed in bespoke editors, and the D9 export

Kits, treasures, monsters mount the shared stack. The registry export writes JSON for the HTML
prototypes; functions (`read`, `write`, `match`, `prose`) cannot be exported, so the export
covers declarative blocks only and marks the rest.

## 10. Risks and open questions for the owner

1. **Logic read-back (4.7).** When a saved feature has three modifiers with the same
   `filterCondition`, should it open as one Logic block around three blocks, or as three blocks
   each with an "Only if" line? Recommendation: group only on an exact string match.
2. **Q2 changes from "first match" to "claims" (4.8).** This reopens a decided item. It is
   required for Combine to read back. Confirm.
3. **C2 touches today's class editor.** It is the only change with a regression surface in
   shipped UI. Acceptable now, or wait for Phase 2?
4. **Save conflicts (section 8).** Is there an engine-side revision or change event for table
   items? If not, the snapshot comparison is the plan, and it only detects a conflict at save
   time.
5. **Filter support per type.** Each modifier block must be checked for whether
   `filterCondition` really applies to it before Logic may wrap it. Who signs that off per
   type?
6. **Functions in declarations cannot reach the HTML prototypes (D9).** Level 3 blocks will be
   missing or stubbed there. Is a declarative-only export enough?
7. **Where the UI lives.** A new `Block Editor` mod keeps the "no type names" rule easy to
   police, but a new mod must be created and ordered in the cloud. The alternative is
   `Draw Steel UI`.
8. **Load order is read from `main.lua`, which can be stale.** Confirm against the CodeMod
   records that `DMHub Utils` loads before `DMHub Game Rules` before registering `Block.lua`.
9. **Templates with literal text between slots** wrap as whole labels. If the visual result is
   poor for long sentences, the fix is in copy (shorter literals), not code.

## 11. What I did not verify

- Whether `filterCondition` is honoured by each of the 62 modifier types (only the mechanism
  was read: `CharacterModifier.lua:4297-4313`).
- The compendium counts quoted in the brief (1,394 power modifiers and so on). They need the
  running app.
- Whether the engine exposes table-item change events or revisions.
- The real cloud load order.
- Drag behaviour between panels in different scroll containers.
